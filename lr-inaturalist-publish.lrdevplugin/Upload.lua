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

local function updateObservation(observation, photo, exportSettings)
	local observationUUID = photo:getPropertyForPlugin(_PLUGIN, MetadataConst.ObservationUUID)
	if observationUUID then
		observation.uuid = observationUUID
	end

	local rootId = exportSettings.syncKeywordsRoot
	if not observation.species_guess and exportSettings.uploadKeywordsSpeciesGuess and rootId and rootId ~= -1 then
		local keywords = photo:getRawMetadata("keywords")
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

	if not observation.latitude then
		local gps = photo:getRawMetadata("gps")
		if gps and photo:getRawMetadata("locationIsPrivate") then
			local uploadPrivateLocation = exportSettings.uploadPrivateLocation
			if uploadPrivateLocation and uploadPrivateLocation ~= "unset" then
				observation.latitude = gps.latitude
				observation.longitude = gps.longitude
				observation.geoprivacy = uploadPrivateLocation
			end
		end
	end

	return observation
end

local function uploadPhoto(api, observations, rendition, path, exportSettings)
	local observationUUID = rendition.photo:getPropertyForPlugin(_PLUGIN, MetadataConst.ObservationUUID)

	if observationUUID and observations[observationUUID] then
		logger:tracef("Updating observation %s", observationUUID)
		-- There's already an observation that was created this session. It's
		-- faster to add an observation photo than upload photo then update the
		-- observation.
		local observation_photo = api:createObservationPhoto(path, observations[observationUUID])
		LrFileUtils.delete(path)
		local observation_stub = {
			id = observations[observationUUID],
			uuid = observationUUID,
		}

		return observation_photo.photo, observation_stub
	end

	-- Either going to create a new obs, or we have a UUID and haven't seen
	-- this obs yet this session.
	-- In either case, POST /observations with local_photos set is safe. In
	-- the latter case it will be added to the list of observation_photos.
	logger:tracef("Creating photo and observation with UUID %s", observationUUID)
	local photo = api:createPhoto(path)
	LrFileUtils.delete(path)
	local observation = updateObservation(photo.to_observation, rendition.photo, exportSettings)
	-- Weirdly the `to_observation` included in the photo response doesn't
	-- include the photo ID
	observation.local_photos = { [0] = { photo.id } }
	observation = api:createObservation(observation)
	logger:tracef("createObservation returned UUID: %s", observation.uuid)

	return photo, observation
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
	local msg = LOC(
		"$$$/iNat/Upload/DeleteOldPhotoError=There was a problem deleting the old version of photo ^1. "
			.. "There may now be duplicate versions on iNaturalist. Error was: ^2",
		photoId,
		result
	)

	LrDialogs.message(LOC("$$$/iNat/Upload/DeleteOldPhotoTitle=Error while updating photo"), msg)
end

function Upload.processRenderedPhotos(_, exportContext)
	local exportSession = exportContext.exportSession
	local exportSettings = exportContext.propertyTable

	local observations = {}
	local api = INaturalistAPI:new(exportSettings.login)
	if exportSettings.syncOnPublish then
		local progress = LrProgressScope({
			title = LOC("$$$/iNat/Upload/SyncingObservations=Synchronizing observations from iNaturalist"),
		})
		local success, err = LrTasks.pcall(SyncObservations.sync, exportSettings, progress, api)
		if not success then
			-- Don't block publish based on sync errors (which could
			-- just be a sync-in-progress)
			logger:error("Sync error during publish:", err)
		end
		progress:done()
	end

	local nPhotos = exportSession:countRenditions()
	local progressScope = exportContext:configureProgress({
		title = LOC("$$$/iNat/Upload/PublishingPhotos=Publishing ^1 photos to iNaturalist", nPhotos),
	})

	for i, rendition in exportContext:renditions({ stopIfCanceled = true }) do
		progressScope:setPortionComplete((i - 1) / nPhotos)
		if not rendition.wasSkipped then
			local success, pathOrMessage = rendition:waitForRender()
			progressScope:setPortionComplete((i - 0.5) / nPhotos)
			if success then
				local previousPhotoId = rendition.publishedPhotoId
				local photo, observation = uploadPhoto(api, observations, rendition, pathOrMessage, exportSettings)
				observations[observation.uuid] = observation.id

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
