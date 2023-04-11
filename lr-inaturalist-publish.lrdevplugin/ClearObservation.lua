local LrApplication = import("LrApplication")
local LrDialogs = import("LrDialogs")

local INaturalistMetadata = require("INaturalistMetadata")

-- Clear the observation UUID field on selected photos
local function clearObservation()
	local catalog = LrApplication.activeCatalog()
	local photos = catalog:getTargetPhotos()

	local confirmation = LrDialogs.confirm(
		"Delete the observation data from " .. #photos .. " photos?",
		"This will clear the observation UUID and URL metadata fields from these photos"
	)

	if confirmation == "cancel" then
		return
	end

	catalog:withWriteAccessDo("Clear observation", function(_)
		for _, photo in pairs(photos) do
			photo:setPropertyForPlugin(_PLUGIN, INaturalistMetadata.ObservationUUID, nil)
			photo:setPropertyForPlugin(_PLUGIN, INaturalistMetadata.ObservationURL, nil)
		end
	end)
end

import("LrTasks").startAsyncTask(clearObservation)
