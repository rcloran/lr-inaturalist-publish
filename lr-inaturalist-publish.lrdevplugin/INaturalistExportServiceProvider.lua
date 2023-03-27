require("strict")

local logger = import("LrLogger")("lr-inaturalist-publish")
local LrFileUtils = import("LrFileUtils")
local LrTasks = import("LrTasks")
local LrView = import("LrView")

local bind = LrView.bind

require("INaturalistUser")

local exportServiceProvider = {
	supportsIncrementalPublish = "only",
	exportPresetFields = {
		{ key = "accessToken", default = "" },
		-- { key = "login", default = "" },
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
	small_icon = 'Resources/inaturalist-icon.png',
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

function exportServiceProvider.processRenderedPhotos(functionContext, exportContext)
	-- The crux of it all.
	local exportSession = exportContext.exportSession
	local exportSettings = exportContext.propertyTable
	local nPhotos = exportSession:countRenditions()
	local progressScope =
		exportContext:configureProgress({ title = string.format("Publishing %i photos to iNaturalist", nPhotos) })


	local api = INaturalistAPI:new(exportSettings.accessToken)
	for i, rendition in exportContext:renditions({ stopIfCanceled = true }) do
		progressScope:setPortionComplete((i - 1) / nPhotos)
		if not rendition.wasSkipped then
			local success, pathOrMessage = rendition:waitForRender()
			progressScope:setPortionComplete((i - 0.75) / nPhotos)
			if success then
				-- We may not need this metadata -- the iNat API
				-- will extract everything from the photo and
				-- provide it back to us in the upload response.
				-- A possible use case might be ensuring GPS
				-- info is published even if it's disabled in
				-- the export prefs -- but that seems like a
				-- dark pattern?
				-- local photo = rendition.photo
				-- local gps = photo:getRawMetadata("gps")
				-- local captureTime = photo:getRawMetadata("dateTimeISO8601")
				-- local caption = photo:getFormattedMetadata("caption")
				local photo = api:createPhoto(pathOrMessage)
				LrFileUtils.delete(pathOrMessage)
				progressScope:setPortionComplete((i - 0.25) / nPhotos)

				-- Weirdly the "to_observation" included in the
				-- photo response doesn't include the photo ID
				local observation = photo.to_observation
				observation.local_photos = {}
				observation.local_photos["0"] = {photo.id}
				observation = api:createObservation(observation)

				rendition:recordPublishedPhotoId(photo.uuid)
				rendition:recordPublishedPhotoUrl("https://www.inaturalist.org/photos/"..photo.id)
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

-- function exportServiceProvider.canAddCommentsToService(publishSettings)
-- return INaturalistAPI.testConnection(publishSettings)
-- end
--

return exportServiceProvider
