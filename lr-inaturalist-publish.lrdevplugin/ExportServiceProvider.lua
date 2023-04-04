require("strict")

local logger = import("LrLogger")("lr-inaturalist-publish")
local LrApplication = import("LrApplication")
local LrDialogs = import("LrDialogs")
local LrFileUtils = import("LrFileUtils")
local LrHttp = import("LrHttp")
local LrProgressScope = import("LrProgressScope")
local LrTasks = import("LrTasks")
local LrView = import("LrView")

local bind = LrView.bind

require("INaturalistMetadata")
require("INaturalistUser")
local SyncObservations = require("SyncObservations")

local exportServiceProvider = {
	supportsIncrementalPublish = "only",
	exportPresetFields = {
		{ key = "accessToken", default = "" },
		{ key = "login", default = "" },
		{ key = "uploadKeywords", default = false },
		{ key = "syncOnPublish", default = true },
		{ key = "syncSearchIn", default = -1 },
	},
	hideSections = {
		"exportLocation",
		"fileNaming",
	},
	allowFileFormats = { "JPEG" },
	-- Not sure if support for more color spaces exists. Keep UI simple
	-- for now...
	allowColorSpaces = { "sRGB" },
	hidePrintResolution = true,
	canExportVideo = false,
	-- Publish provider options
	small_icon = "Resources/inaturalist-icon.png",
	titleForGoToPublishedCollection = "Go to observations in iNaturalist",
}

local function updateCantExportBecause(propertyTable)
	if propertyTable.accessToken == "" then
		propertyTable.LR_cantExportBecause = "Not logged in to iNaturalist"
		return
	end

	propertyTable.LR_cantExportBecause = nil
end

-- called when the user picks this service in the publish dialog
function exportServiceProvider.startDialog(propertyTable)
	propertyTable:addObserver("accessToken", function()
		updateCantExportBecause(propertyTable)
	end)
	updateCantExportBecause(propertyTable)

	INaturalistUser.verifyLogin(propertyTable)
end

local function getCollectionsForPopup(parent, indent)
	local r = {}
	local children = parent:getChildCollections()
	for i = 1, #children do
		if not children[i]:isSmartCollection() then
			r[#r + 1] = {
				title = indent .. children[i]:getName(),
				value = children[i].localIdentifier,
			}
		end
	end

	children = parent:getChildCollectionSets()
	for i = 1, #children do
		local childrenItems = getCollectionsForPopup(children[i], indent .. "  ")
		if #childrenItems > 0 then
			r[#r + 1] = {
				title = indent .. children[i]:getName(),
				value = children[i].localIdentifier,
			}
			for i = 1, #childrenItems do
				r[#r + 1] = childrenItems[i]
			end
		end
	end

	return r
end

function exportServiceProvider.sectionsForTopOfDialog(f, propertyTable)
	LrTasks.startAsyncTask(function()
		local cat = LrApplication.activeCatalog()
		local r = { {
			title = "--",
			value = -1,
		} }
		local items = getCollectionsForPopup(cat, "")
		for i = 1, #items do
			r[#r + 1] = items[i]
		end
		propertyTable.syncSearchInItems = r
	end)

	local account = {
		title = "iNaturalist Account",
		synopsis = "Account status",
		f:row({
			spacing = f:control_spacing(),
			f:static_text({
				title = bind("accountStatus"),
				alignment = "right",
				fill_horizontal = 1,
			}),
			f:push_button({
				title = bind("loginButtonTitle"),
				enabled = bind("loginButtonEnabled"),
				action = function()
					INaturalistUser.login(propertyTable)
				end,
			}),
		}),
	}
	local options = {
		title = "Export options",
		f:row({
			spacing = f:control_spacing(),
			f:static_text({
				title = "Export Lightroom keywords as iNaturalist tags",
				alignment = "right",
				width = LrView.share("inaturalistSyncLabel"),
			}),
			f:checkbox({
				value = bind("uploadKeywords"),
				alignment = "left",
			}),
		}),
	}
	local synchronization = {
		title = "iNaturalist Synchronization",
		f:row({
			spacing = f:control_spacing(),
			f:static_text({
				title = "These options control how changes on iNaturalist are synchronized into your catalog.",
				height_in_lines = -1,
				fill_horizontal = 1,
			}),
		}),
		f:row({
			f:static_text({
				title = "Help...",
				width_in_chars = 0,
				alignment = "right",
				text_color = import("LrColor")(0, 0, 1),
				mouse_down = function()
					LrHttp.openUrlInBrowser("https://github.com/rcloran/lr-inaturalist-publish/wiki/Synchronization")
				end,
			}),
		}),
		f:row({
			spacing = f:control_spacing(),
			f:static_text({
				title = "Only search for photos to sync from iNaturalist in",
				alignment = "right",
				width = LrView.share("inaturalistSyncLabel"),
			}),
			f:popup_menu({
				value = bind("syncSearchIn"),
				items = bind("syncSearchInItems"),
			}),
		}),
		f:row({
			spacing = f:control_spacing(),
			f:static_text({
				title = "Synchronize from iNaturalist during every publish",
				alignment = "right",
				width = LrView.share("inaturalistSyncLabel"),
			}),
			f:checkbox({
				value = bind("syncOnPublish"),
			}),
		}),
		f:separator({ fill_horizontal = 1 }),
		f:row({
			spacing = f:control_spacing(),
			f:static_text({
				title = "Synchronize everything from iNaturalist, even if it might not have changed:",
				height_in_lines = -1,
				alignment = "right",
				width = LrView.share("inaturalistSyncLabel"),
				enabled = bind("LR_editingExistingPublishConnection"),
			}),
			f:push_button({
				title = "Full synchronization now",
				action = function()
					LrTasks.startAsyncTask(function()
						SyncObservations.fullSync(propertyTable)
					end)
				end,
				enabled = bind("LR_editingExistingPublishConnection"),
			}),
		}),
		f:row({
			spacing = f:control_spacing(),
			f:static_text({
				title = "Synchronize changes since last sync:",
				height_in_lines = -1,
				alignment = "right",
				width = LrView.share("inaturalistSyncLabel"),
				enabled = bind("LR_editingExistingPublishConnection"),
			}),
			f:push_button({
				title = "Synchronize now",
				action = function()
					LrTasks.startAsyncTask(function()
						SyncObservations.sync(propertyTable)
					end)
				end,
				enabled = bind("LR_editingExistingPublishConnection"),
			}),
		}),
	}

	return { account, options, synchronization }
end

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

	if exportSettings.uploadKeywords then
		local keywords = photo:getRawMetadata("keywords")
		if keywords and #keywords > 0 then
			local tagList = keywords[1]:getName()
			for i = 2, #keywords do
				tagList = tagList .. "," .. keywords[i]:getName()
			end
			observation.tag_list = tagList
		end
	end

	local observationUUID = photo:getPropertyForPlugin(_PLUGIN, INaturalistMetadata.ObservationUUID)
	if observationUUID then
		observation.uuid = observationUUID
	end

	return observation
end

local function uploadPhoto(api, observations, rendition, path, exportSettings)
	local localObservationUUID = rendition.photo:getPropertyForPlugin(_PLUGIN, INaturalistMetadata.ObservationUUID)

	if localObservationUUID and observations[localObservationUUID] then
		-- In this case there's already an observation this session
		local observation_photo = api:createObservationPhoto(path, observations[localObservationUUID])
		LrFileUtils.delete(path)
		local observation_stub = {
			id = observations[localObservationUUID],
			uuid = localObservationUUID,
		}

		return observation_photo.photo, observation_stub
	end

	-- In this case we might have linked a new photo to an existing
	-- observation, or it might be a new observation. In the former case,
	-- POST to /observations will update the old observation, so we can
	-- just do that. Any updated fields will change to the new value, but
	-- if they're blank we omit them in the POST so they should stay.
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
	local success, result = LrTasks.pcall(function()
		api:deletePhoto(photoId)
	end)

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
	local success, result = LrTasks.pcall(function()
		saferDelete(api, photoId)
	end)

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

function exportServiceProvider.processRenderedPhotos(functionContext, exportContext)
	local exportSession = exportContext.exportSession
	local exportSettings = exportContext.propertyTable

	local observations = {}
	local api = INaturalistAPI:new(exportSettings.accessToken)
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
					lrPhoto:setPropertyForPlugin(_PLUGIN, INaturalistMetadata.ObservationUUID, observation.uuid)
					local observation_url = "https://www.inaturalist.org/observations/" .. observation.id
					lrPhoto:setPropertyForPlugin(_PLUGIN, INaturalistMetadata.ObservationURL, observation_url)
				end)
			end
		end
	end

	progressScope:done()
end

-- Publish provider functions
function exportServiceProvider.metadataThatTriggersRepublish(publishSettings)
	local r = {
		default = false,
		caption = true,
		dateCreated = true,
		gps = true,
		keywords = publishSettings.uploadKeywords,
	}

	return r
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
		local uuid = photo:getPropertyForPlugin(_PLUGIN, INaturalistMetadata.ObservationUUID)
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

function exportServiceProvider.deletePhotosFromPublishedCollection(
	publishSettings,
	photoIds,
	deletedCallback,
	localCollectionId
)
	logger:trace("deletePhotosFromPublishedCollection(...)")
	local catalog = LrApplication.activeCatalog()
	local collection = catalog:getPublishedCollectionByLocalIdentifier(localCollectionId)

	local api = INaturalistAPI:new(publishSettings.accessToken)

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

function exportServiceProvider.getCollectionBehaviorInfo(publishSettings)
	return {
		defaultCollectionName = "Observations",
		defaultCollectionCanBeDeleted = false,
		canAddCollection = false,
		maxCollectionSetDepth = 0,
	}
end

function exportServiceProvider.goToPublishedCollection(publishSettings, info)
	LrHttp.openUrlInBrowser("https://www.inaturalist.org/observations/" .. publishSettings.login)
end

function exportServiceProvider.didCreateNewPublishService(publishSettings, info)
	local f = LrView.osFactory()
	local mainMsg = "This will take some time."
	if publishSettings.syncOnPublish then
		mainMsg =
			"This will take some time. If you do not do this now it will happen automatically the first time you publish using this plugin."
	end
	local c = {
		spacing = f:dialog_spacing(),
		f:static_text({
			title = mainMsg,
			fill_horizontal = 1,
			width_in_chars = 50,
			height_in_lines = 2,
		}),
	}
	if publishSettings.syncSearchIn == -1 then
		c[#c + 1] = f:static_text({
			title = "You have not set a collection to which to limit the search for matching photos. This may result in a low number of matches.",
			fill_horizontal = 1,
			width_in_chars = 50,
			height_in_lines = 2,
		})
	end
	local r = LrDialogs.presentModalDialog({
		title = "Perform synchronization from iNaturalist now?",
		contents = f:column(c),
	})

	if r == "ok" then
		SyncObservations.fullSync(publishSettings)
	end
end

-- function exportServiceProvider.canAddCommentsToService(publishSettings)
-- return INaturalistAPI.testConnection(publishSettings)
-- end
--

return exportServiceProvider
