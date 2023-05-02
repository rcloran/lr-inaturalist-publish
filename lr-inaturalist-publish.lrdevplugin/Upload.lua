local logger = import("LrLogger")("lr-inaturalist-publish")
local LrApplication = import("LrApplication")
local LrDialogs = import("LrDialogs")
local LrFileUtils = import("LrFileUtils")
local LrProgressScope = import("LrProgressScope")
local LrTasks = import("LrTasks")

local INaturalistAPI = require("INaturalistAPI")
local MetadataConst = require("MetadataConst")
local SyncObservations = require("SyncObservations")

local Upload = {}

local function makeObservationObj(photo, exportSettings)
	local observation = {}

	local dateTimeISO8601 = photo:getRawMetadata("dateTimeISO8601")
	if dateTimeISO8601 and #dateTimeISO8601 > 0 then
		observation.observed_on_string = dateTimeISO8601
	end

	local description = photo:getFormattedMetadata("caption")
	if description and #description > 0 then
		observation.description = description
	end

	local gps = photo:getRawMetadata("gps")
	if gps then
		observation.latitude = gps.latitude
		observation.longitude = gps.longitude
	end

	local keywords = photo:getRawMetadata("keywords")
	if exportSettings.uploadKeywords then
		if keywords and #keywords > 0 then
			local tagList = keywords[1]:getName()
			for i = 2, #keywords do
				tagList = tagList .. "," .. keywords[i]:getName()
			end
			observation.tag_list = tagList
		end
	end

	local rootId = exportSettings.syncKeywordsRoot
	if exportSettings.uploadKeywordsSpeciesGuess and rootId and rootId ~= -1 then
		for _, kw in pairs(keywords) do
			-- If multiple are set we'll end up using the last one
			if SyncObservations.kwIsParentedBy(kw, rootId) then
				if exportSettings.syncKeywordsCommon and #kw:getSynonyms() >= 1 then
					observation.species_guess = kw:getSynonyms()[1]
				else
					observation.species_guess = kw:getName()
				end
			end
		end
	end

	local observationUUID = photo:getPropertyForPlugin(_PLUGIN, MetadataConst.ObservationUUID)
	if observationUUID then
		observation.uuid = observationUUID
	end

	return observation
end

local function uploadPhoto(api, observations, rendition, path, exportSettings)
	local localObservationUUID = rendition.photo:getPropertyForPlugin(_PLUGIN, MetadataConst.ObservationUUID)

	if localObservationUUID and observations[localObservationUUID] then
		-- There's already an observation that was created this session
		local observation_photo = api:createObservationPhoto(path, observations[localObservationUUID])
		LrFileUtils.delete(path)
		local observation_stub = {
			id = observations[localObservationUUID],
			uuid = localObservationUUID,
		}

		return observation_photo.photo, observation_stub
	end

	-- We might have linked a new photo to an existing observation, or it might
	-- be a new observation. In the former case, POST to /observations will
	-- update the old observation, so we can just do that. Any updated fields
	-- will change to the new value, but if they're blank we omit them in the
	-- POST so they should stay.
	local observation = makeObservationObj(rendition.photo, exportSettings)
	observation = api:createObservation(observation)

	-- Record the observation for this session
	observations[observation.uuid] = observation.id

	-- Upload the photo
	local observation_photo = api:createObservationPhoto(path, observation.id)
	LrFileUtils.delete(path)

	return observation_photo.photo, observation
end

local function saferDelete(api, photoId)
	local success, result = LrTasks.pcall(api.deletePhoto, api, photoId)

	-- If we get a 404 on delete, that's the state we wanted anyways, so
	-- treat it as success.
	if success or result.code == 404 then
		return
	end
	error(result)
end

local function maybeDeleteOld(api, photoId)
	if not photoId then
		return
	end

	logger:infof("Deleting photo %s (updated)", photoId)
	local success, result = LrTasks.pcall(saferDelete, api, photoId)

	if success then
		return
	end

	-- If we get an error here I think it's better to continue
	-- updates/publishes instead of letting the error bubble up? Just tell
	-- the user.
	local msg = string.format(
		"There was a problem deleting the old version of photo %s. "
			.. "There may now be duplicate versions on iNaturalist. "
			.. "Error was: %s",
		photoId,
		result
	)

	LrDialogs.message("Error while updating photo", msg)
end

function Upload.processRenderedPhotos(_, exportContext)
	local exportSession = exportContext.exportSession
	local exportSettings = exportContext.propertyTable

	local observations = {}
	local api = INaturalistAPI:new(exportSettings.login)
	if exportSettings.syncOnPublish then
		local progress = LrProgressScope({
			title = "Synchronizing observations from iNaturalist",
		})
		local success, obsList = LrTasks.pcall(SyncObservations.sync, exportSettings, progress, api)
		if not success then
			-- Don't block publish based on sync errors (which could
			-- just be a sync-in-progress)
			logger:error("Sync error during publish:", obsList)
			obsList = {}
		end

		-- This might save some POSTs to unnecessarily update existing
		-- observations.
		for _, o in ipairs(obsList) do
			observations[o.uuid] = o.id
		end
		progress:done()
	end

	local nPhotos = exportSession:countRenditions()
	local progressScope = exportContext:configureProgress({
		title = string.format("Publishing %i photos to iNaturalist", nPhotos),
	})

	for i, rendition in exportContext:renditions({ stopIfCanceled = true }) do
		progressScope:setPortionComplete((i - 1) / nPhotos)
		if not rendition.wasSkipped then
			local success, pathOrMessage = rendition:waitForRender()
			progressScope:setPortionComplete((i - 0.5) / nPhotos)
			if success then
				local previousPhotoId = rendition.publishedPhotoId
				local photo, observation = uploadPhoto(api, observations, rendition, pathOrMessage, exportSettings)

				maybeDeleteOld(api, previousPhotoId)

				rendition:recordPublishedPhotoId(photo.id)
				rendition:recordPublishedPhotoUrl("https://www.inaturalist.org/photos/" .. photo.id)

				local lrPhoto = rendition.photo
				lrPhoto.catalog:withPrivateWriteAccessDo(function()
					lrPhoto:setPropertyForPlugin(_PLUGIN, MetadataConst.ObservationUUID, observation.uuid)
					local observation_url = "https://www.inaturalist.org/observations/" .. observation.id
					lrPhoto:setPropertyForPlugin(_PLUGIN, MetadataConst.ObservationURL, observation_url)
				end)
			end
		end
	end

	progressScope:done()
end

local function getObservationsForPhotos(api, collection, photos)
	-- Urgh. No way to search by remoteId, and we need the observation
	for _, photo in pairs(collection:getPublishedPhotos()) do
		if photos[photo:getRemoteId()] then
			photos[photo:getRemoteId()] = photo:getPhoto()
		end
	end

	-- Retrieve all the observations (1 by 1!? TODO: Batch.)
	local observations = {}
	for _, photo in pairs(photos) do
		local uuid = photo:getPropertyForPlugin(_PLUGIN, MetadataConst.ObservationUUID)
		if uuid and not observations[uuid] then
			local listedObservations = api:listObservations({ uuid = uuid })
			if #listedObservations == 1 then
				observations[uuid] = listedObservations[1]
			else
				-- The only possibility here /should/ be 0,
				-- in which case there's nothing to delete
				-- anyways.
				logger:infof("Found %s observations when searching for %s (expected 1)", #listedObservations, uuid)
			end
		end
	end

	return observations
end

function Upload.deletePhotosFromPublishedCollection(publishSettings, photoIds, deletedCallback, localCollectionId)
	logger:trace("deletePhotosFromPublishedCollection(...)")
	local catalog = LrApplication.activeCatalog()
	local collection = catalog:getPublishedCollectionByLocalIdentifier(localCollectionId)

	local api = INaturalistAPI:new(publishSettings.login)

	-- Turn photoIds into a set
	local photos = {}
	for i = 1, #photoIds do
		photos[photoIds[i]] = true
	end

	local observations = getObservationsForPhotos(api, collection, photos)

	-- Delete the observations where we're deleting all the photos attached
	-- to that observation.
	for _, observation in pairs(observations) do
		local deletingAllPhotos = true
		for _, photo in pairs(observation.photos) do
			deletingAllPhotos = deletingAllPhotos and photos[photo.id]
		end

		if deletingAllPhotos then
			logger:infof("Deleting observation %s %s", observation.id, observation.uuid)
			api:deleteObservation(observation.id)
			-- Deleting the observation automagically deletes
			-- associated photos
			for _, photo in pairs(observation.photos) do
				deletedCallback(photo.id)
				photos[photo.id] = nil
			end
		end
	end
	for photoId, _ in pairs(photos) do
		logger:infof("Deleting photo %s", photoId)
		saferDelete(api, photoId) -- Let errors bubble up
		deletedCallback(photoId)
	end
end

return Upload
