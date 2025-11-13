local LrApplication = import("LrApplication")
local LrDialogs = import("LrDialogs")

local MetadataConst = require("MetadataConst")

-- Clear the observation UUID field on selected photos
local function clearObservation()
	local catalog = LrApplication.activeCatalog()
	local photos = catalog:getTargetPhotos()

	local confirmation = LrDialogs.confirm(
		LOC("$$$/iNat/Clear/DeleteObservationData=Delete the observation data from ^1 photos?", #photos),
		LOC(
			"$$$/iNat/Clear/ClearFieldsInfo=This will clear the observation UUID and URL metadata "
				.. "fields from these photos"
		)
	)

	if confirmation == "cancel" then
		return
	end

	catalog:withWriteAccessDo("Clear observation", function(_)
		for _, photo in pairs(photos) do
			photo:setPropertyForPlugin(_PLUGIN, MetadataConst.ObservationUUID, nil)
			photo:setPropertyForPlugin(_PLUGIN, MetadataConst.ObservationURL, nil)
		end
		local msg = LOC("$$$/iNat/Clear/RemovedMetadataPlural=Removed observation metadata from ^1 photos")
		if #photos == 1 then
			msg = LOC("$$$/iNat/Clear/RemovedMetadataSingular=Removed observation metadata from ^1 photo")
		end
		LrDialogs.showBezel(string.format(msg, #photos))
	end)
end

import("LrTasks").startAsyncTask(clearObservation)
