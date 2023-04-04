local logger = import("LrLogger")("lr-inaturalist-publish")
local LrApplication = import("LrApplication")
local LrDialogs = import("LrDialogs")
local LrDate = import("LrDate")
local LrFunctionContext = import("LrFunctionContext")
local LrProgressScope = import("LrProgressScope")

require("INaturalistAPI")
require("INaturalistMetadata")

SyncObservations = {}

local function commonName(taxon)
	-- TODO: Find proper translations for names. For now, be English-centric
	-- because preferred_common_name seems to be inconsistent.
	return taxon.english_common_name or taxon.preferred_common_name or taxon.name
end

local function observationCommonName(obs)
	return commonName(obs.taxon)
end

local function observationName(obs)
	return obs.taxon.name
end

local allowedRanks = {
	kingdom = true,
	class = true,
	order = true,
	family = true,
	genus = true,
	species = true,
	subspecies = true,
}

local function ancestorIds(t)
	-- This will mess with the contents of t.ancestor_ids
	local ancestor_ids = t.ancestor_ids
	if t.id ~= ancestor_ids[#ancestor_ids] then
		ancestor_ids[#ancestor_ids + 1] = t.id
	end
	if ancestor_ids[1] == 48460 then -- Life
		table.remove(ancestor_ids, 1)
	end
	return ancestor_ids
end

local function isPrefix(short, long)
	for i = 1, #short do
		if short[i] ~= long[i] then
			return false
		end
	end
	return true
end

local function walkTaxonomy(obs, callback)
	local taxonAncestorIds = ancestorIds(obs.taxon)
	for _, identification in pairs(obs.identifications) do
		if isPrefix(taxonAncestorIds, ancestorIds(identification.taxon)) then
			-- Ancestors here are actually ancestors, they don't include
			-- the ID, so go to -1.
			for i = 1, #taxonAncestorIds - 1 do
				local ancestor = identification.taxon.ancestors[i]
				if allowedRanks[ancestor.rank] then
					callback(ancestor)
				end
			end
			callback(obs.taxon)
			return
		end
	end
end

local function observationCommonTaxonomy(obs)
	local r = ""
	walkTaxonomy(obs, function(taxon)
		r = r .. commonName(taxon) .. "|"
	end)
	return r:sub(1, -2)
end

local function observationTaxonomy(obs)
	local r = ""
	walkTaxonomy(obs, function(taxon)
		r = r .. taxon.name .. "|"
	end)
	return r:sub(1, -2)
end

local function setObservationMetadata(obs, photo)
	if not (obs.taxon and obs.identifications and #obs.identifications > 0) then
		return
	end
	photo:setPropertyForPlugin(_PLUGIN, INaturalistMetadata.CommonName, observationCommonName(obs))
	photo:setPropertyForPlugin(_PLUGIN, INaturalistMetadata.Name, observationName(obs))
	photo:setPropertyForPlugin(_PLUGIN, INaturalistMetadata.CommonTaxonomy, observationCommonTaxonomy(obs))
	photo:setPropertyForPlugin(_PLUGIN, INaturalistMetadata.Taxonomy, observationTaxonomy(obs))
end

local ISO8601Pattern = "(%d+)%-(%d+)%-(%d+)%a(%d+)%:(%d+)%:([%d%.]+)([Z%+%-])(%d?%d?)%:?(%d?%d?)"

local function parseISO8601(s)
	local year, month, day, hour, minute, second, tzsign, tzhour, tzminute = s:match(ISO8601Pattern)
	local tz = 0
	if tzsign ~= "Z" then
		tz = ((tzhour * 60) + tzminute) * 60
		if tzsign == "-" then
			tz = tz * -1
		end
	end

	return LrDate.timeFromComponents(year, month, day, hour, minute, second, tz)
end

local function toISO8601(t)
	if t == nil then
		return nil
	end
	local v = LrDate.timeToW3CDate(t) .. "Z"
	return v
end

local function timezoneless(t)
	local year, month, day, hour, minute, second, _, _, _ = t:match(ISO8601Pattern)
	return string.format("%s-%s-%sT%s:%s:%s", year, month, day, hour, minute, second)
end

local function withWriteAccessDo(actionName, func, timeoutParams)
	local catalog = LrApplication.activeCatalog()
	if catalog.hasWriteAccess then
		func()
	else
		catalog:withWriteAccessDo(actionName, func, timeoutParams)
	end
end

local function withPrivateWriteAccessDo(func, timeoutParams)
	local catalog = LrApplication.activeCatalog()
	if catalog.hasPrivateWriteAccess then
		func()
	else
		catalog:withPrivateWriteAccessDo(func, timeoutParams)
	end
end

local function getCollection(publishSettings)
	-- We can't save a value on settings outside of the publishing manager.
	-- It's tempting to use the plugin prefs, but AFAICT those don't exist
	-- in the catalog, so we'd have conflicting settings.
	-- I think the next most convenient place is in the collection.

	-- When using the publish manager, this is the fastest way to get the
	-- publishService
	local publishService = publishSettings.LR_publishService
	if not publishService then
		-- But when actually publishing, that's not set, so do some
		-- digging.
		local publishConnectionName = publishSettings.LR_publish_connectionName
		for _, ps in pairs(LrApplication.activeCatalog():getPublishServices(_PLUGIN.id)) do
			if ps:getName() == publishConnectionName then
				publishService = ps
			end
		end
		if not publishService then
			-- Give up.
			return nil
		end
	end

	local c = publishService:getChildCollections()
	assert(#c == 1)

	return c[1]
end

local function getLastSync(publishSettings)
	-- Note that if you call this from within the same transaction as a
	-- setLastSync, it'll return the old value.
	local c = getCollection(publishSettings)
	if not c then
		return nil
	end

	return c:getCollectionInfoSummary().collectionSettings.lastSync
end

local function setLastSync(publishSettings, lastSync)
	local c = getCollection(publishSettings)
	if not c then
		return
	end

	local s = c:getCollectionInfoSummary().collectionSettings
	s.lastSync = lastSync
	logger:trace("Saving last sync...")
	withPrivateWriteAccessDo(function()
		c:setCollectionSettings(s)
	end, { timeout = 30 })
end

local function makePhotoSearchQuery(observation, pubCollection)
	-- The LR data is timezoneless (at least in search).
	-- I think it's correct to query it without the TZ from iNaturalist,
	-- since from what I've seen there can be a mismatch in TZ between the
	-- two (I think iNat respects DST at the location, not sure), but the
	-- timezoneless timestamp matches.
	local timeObserved = timezoneless(observation.time_observed_at)
	if timeObserved:sub(-2, -1) == "00" then
		-- Observations created with the web interface only have minute
		-- granulatiry. Fortunately the LR date search uses a prefix
		-- match (compare a search for "2023-04-01T14:1" with
		-- "2023-04-01T14:01" and "2023-04-01T14:10").
		timeObserved = timeObserved:sub(1, -4)
	end
	local r = {
		combine = "union",
		{
			criteria = "sdktext:" .. _PLUGIN.id .. "." .. INaturalistMetadata.ObservationUUID,
			operation = "==",
			value = observation.uuid,
		},
		{
			criteria = "captureTime",
			operation = "==",
			value = timeObserved,
		},
	}

	return r
end

local matchStats = {}
local syncInProgress = false

local function filterMatchedPhotos(observation, photos, filterCollection)
	local r = {}
	for _, photo in pairs(photos) do
		if photo:getPropertyForPlugin(_PLUGIN, INaturalistMetadata.ObservationUUID) == observation.uuid then
			r[#r + 1] = photo
		end
	end

	-- We searched for UUID *or* time match, but if there's at least one
	-- UUID match, return those as the actual matches and forget the time
	-- matches.
	if #r > 0 then
		matchStats["uuid"] = (matchStats["uuid"] or 0) + #r
		return r, true
	end

	-- Only fall through to a less certain match if we were unsure about
	-- which photos in the catalog were actually published to the
	-- observation.
	for _, photo in pairs(photos) do
		-- Searching based on collection is slow, this seems faster
		local collections = photo:getContainedCollections()
		for _, c in pairs(photo:getContainedCollections()) do
			if c.localIdentifier == filterCollection then
				r[#r + 1] = photo
			end
		end
	end
	photos, r = r, {}

	-- We already matched time in the search, don't need to double check it
	-- here.
	if #photos == 1 then
		matchStats["time"] = (matchStats["time"] or 0) + 1
		return photos, false
	end

	-- Maybe we can refine based on GPS data?
	if observation.geojson and observation.geojson.type == "Point" then
		local obsGPS = observation.geojson.coordinates

		for _, photo in pairs(photos) do
			local photoGPS = photo:getRawMetadata("gps")
			if photoGPS then
				local gpsMatch = obsGPS[2] == photoGPS.latitude and obsGPS[1] == photoGPS.longitude

				if gpsMatch then
					r[#r + 1] = photo
				end
			end
		end
	end

	if #r == 1 then
		matchStats["time+gps"] = (matchStats["time+gps"] or 0) + 1
		return r, false
	end

	local matchSoFar = "time"
	if #r ~= 0 then
		-- If we have at least one match by GPS, continue refining
		-- those instead of looking at all photos for crop.
		photos, r = r, {}
		matchSoFar = "time+gps"
	end

	-- We still have too many matches. Maybe we can refine by how much the
	-- user cropped one in a burst?
	for _, photo in pairs(photos) do
		local photoDims = photo:getRawMetadata("croppedDimensions")
		local foundOneObsPhoto = false
		for _, obsPhoto in pairs(observation.observation_photos) do
			local obsDims = obsPhoto.photo.original_dimensions
			if
				not foundOneObsPhoto
				and math.abs(obsDims.width - photoDims.width) < 2
				and math.abs(obsDims.height - photoDims.height) < 2
			then
				r[#r + 1] = photo
				foundOneObsPhoto = true
			end
		end
	end

	if #r == 1 then
		matchStats[matchSoFar .. "+crop"] = (matchStats[matchSoFar .. "+crop"] or 0) + 1
		return r, false
	end

	matchStats["none"] = (matchStats["none"] or 0) + 1
	return {}, false
end

local function sync(functionContext, settings, progress, api, lastSync)
	if syncInProgress then
		error("A sync from iNaturalist is already in progress")
	end
	syncInProgress = true
	functionContext:addCleanupHandler(function()
		syncInProgress = false
		progress:done()
	end)

	logger:info("Synchronizing from iNaturalist")
	local catalog = LrApplication.activeCatalog()
	local collection = getCollection(settings)

	matchStats = {}

	if not api then
		api = INaturalistAPI:new(settings.accessToken)
	end

	local query = {
		user_login = settings.login,
		updated_since = toISO8601(lastSync),
	}

	local dlProgress = LrProgressScope({
		caption = "Downloading observations",
		parent = progress,
		parentEndRange = 0.5,
	})
	dlProgress.setCaption = function(self, caption)
		-- I don't understand the API docs on how captions for child
		-- scopes are supposed to work. Setting the parent scope's
		-- caption seems to do what I actually want.
		progress:setCaption(caption)
	end
	local observations = api:listObservationsWithPagination(query, dlProgress)

	-- Now apply downloaded data to the catalog
	local syncProgress = LrProgressScope({
		caption = "Setting observation data",
		parent = progress,
		parentEndRange = 1,
	})
	local mostRecentUpdate = 0
	local collectionPhotos = {}
	for _, photo in pairs(collection:getPhotos()) do
		collectionPhotos[photo.localIdentifier] = true
	end
	for i = 1, #observations do
		if syncProgress:isCanceled() then
			-- Lightroom seems to not present dialogs if you give a table as error,
			-- which is nice in this case.
			error({ code = "canceled", message = "Canceled by user" })
		end
		local observation = observations[i]

		local updated = parseISO8601(observation.updated_at)
		if updated > mostRecentUpdate then
			mostRecentUpdate = updated
		end

		local searchDesc = makePhotoSearchQuery(observation, collection)
		local photos = catalog:findPhotos({ searchDesc = searchDesc })
		local matchedByUUID = false
		photos, matchedByUUID = filterMatchedPhotos(observation, photos, settings.syncSearchIn)

		if #photos == 1 or matchedByUUID then
			for _, photo in pairs(photos) do
				withPrivateWriteAccessDo(function()
					setObservationMetadata(observation, photo)
					photo:setPropertyForPlugin(_PLUGIN, INaturalistMetadata.ObservationUUID, observation.uuid)
					local observation_url = "https://www.inaturalist.org/observations/" .. observation.id
					photo:setPropertyForPlugin(_PLUGIN, INaturalistMetadata.ObservationURL, observation_url)
				end)
			end
			if #photos == 1 and #observation.photos == 1 and not collectionPhotos[photos[1].localIdentifier] then
				local oP = observation.photos[1]
				withWriteAccessDo("Add photo to observations", function()
					collection:addPhotoByRemoteId(
						photos[1],
						oP.id,
						"https://www.inaturalist.org/photos/" .. oP.id,
						true
					)
				end, { timeout = 3 })
			end
		end

		syncProgress:setPortionComplete(i / #observations)
		if i % 3 == 0 then
			progress:setCaption("Updating photos from observation data (" .. i .. "/" .. #observations .. ")")
		end
	end

	logger:debug("matchStats:")
	for k, v in pairs(matchStats) do
		logger:debug("", k, v)
	end

	if #observations > 0 then
		setLastSync(settings, mostRecentUpdate)
	end

	syncProgress:done()

	return observations
end

function SyncObservations.sync(settings, progress, api)
	local lastSync = getLastSync(settings)
	if not lastSync then
		-- Get prolonged write access if we're doing a full sync
		return SyncObservations.fullSync(settings, progress, api)
	end

	return LrFunctionContext.callWithContext("SyncObservations.sync", function(context)
		if not progress then
			progress = LrDialogs.showModalProgressDialog({
				title = "Synchronizing from iNaturalist",
				cannotCancel = false,
				functionContext = context,
			})
		end

		return sync(context, settings, progress, api, lastSync)
	end)
end

function SyncObservations.fullSync(settings, progress, api)
	local catalog = LrApplication.activeCatalog()
	local observations = {}
	catalog:withProlongedWriteAccessDo({
		title = "Synchronizing from iNaturalist",
		pluginName = "iNaturalist Publish Service Provider",
		func = function(context, progress)
			setLastSync(settings, nil) -- Inside transaction, so that if it fails...
			observations = sync(context, settings, progress, api, nil)
		end,
	})
	return observations
end

return SyncObservations
