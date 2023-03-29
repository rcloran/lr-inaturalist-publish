require("strict")

local logger = import("LrLogger")("lr-inaturalist-publish")
local LrFileUtils = import("LrFileUtils")
local LrHttp = import("LrHttp")
local LrTasks = import("LrTasks")
local LrView = import("LrView")

local bind = LrView.bind

require("INaturalistMetadata")
require("INaturalistUser")

local exportServiceProvider = {
	supportsIncrementalPublish = "only",
	exportPresetFields = {
		{ key = "accessToken", default = "" },
		{ key = "login", default = "" },
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
	if not propertyTable.accessToken then
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

	INaturalistUser.verifyLogin(propertyTable)
end

function exportServiceProvider.sectionsForTopOfDialog(f, propertyTable)
	return {
		{
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
		},
	}
end

local function makeObservationObj(photo)
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
	if keywords and #keywords > 0 then
		observation.tag_list = {}
		for i = 1, #keywords do
			table.insert(tag_list, keywords[i]:getName())
		end
	end

	local observationUUID = photo:getPropertyForPlugin(_PLUGIN, INaturalistMetadata.ObservationUUID)
	if observationUUID then
		observation.uuid = observationUUID
	end

	return observation
end

local function uploadPhoto(api, observations, rendition, path)
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
	local observation = makeObservationObj(rendition.photo)
	observation = api:createObservation(observation)

	-- Record the observation for this session
	observations[observation.uuid] = observation.id

	-- Upload the photo
	local observation_photo = api:createObservationPhoto(path, observation.id)
	LrFileUtils.delete(path)

	return observation_photo.photo, observation
end

function exportServiceProvider.processRenderedPhotos(functionContext, exportContext)
	-- The crux of it all.
	local exportSession = exportContext.exportSession
	local exportSettings = exportContext.propertyTable
	local nPhotos = exportSession:countRenditions()
	local progressScope =
		exportContext:configureProgress({ title = string.format("Publishing %i photos to iNaturalist", nPhotos) })

	local observations = {}
	local api = INaturalistAPI:new(exportSettings.accessToken)
	for i, rendition in exportContext:renditions({ stopIfCanceled = true }) do
		progressScope:setPortionComplete((i - 1) / nPhotos)
		if not rendition.wasSkipped then
			local success, pathOrMessage = rendition:waitForRender()
			progressScope:setPortionComplete((i - 0.5) / nPhotos)
			if success then
				local photo, observation = uploadPhoto(api, observations, rendition, pathOrMessage)

				rendition:recordPublishedPhotoId(photo.uuid)
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
	return {
		default = false,
		caption = true,
		dateCreated = true, -- !?
		gps = true, -- !?
	}
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

-- function exportServiceProvider.canAddCommentsToService(publishSettings)
-- return INaturalistAPI.testConnection(publishSettings)
-- end
--

return exportServiceProvider
