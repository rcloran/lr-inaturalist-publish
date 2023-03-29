local logger = import("LrLogger")("lr-inaturalist-publish")
local LrApplication = import("LrApplication")
local LrDialogs = import("LrDialogs")

require("INaturalistMetadata")

-- Group photos into an observation. That is, assign observation UUIDs.
local function groupObservation()
	local catalog = LrApplication.activeCatalog()
	local photos = catalog:getTargetPhotos()

	if #photos <= 1 then
		LrDialogs.message("Please select more than 1 photo to group")
		return
	end

	local uuid = nil
	for _, photo in pairs(photos) do
		local existingUUID = photo:getPropertyForPlugin(_PLUGIN, INaturalistMetadata.ObservationUUID)
		if existingUUID and #existingUUID > 0 then
			if uuid ~= nil and uuid ~= existingUUID then
				LrDialogs.message(
					"Conflicting observations",
					"Two photos in the selection already belong to different observations"
				)
				return
			end
			uuid = existingUUID
		end
	end

	if uuid == nil then
		uuid = UUID.uuid4()
	end

	catalog:withWriteAccessDo("Group into observation", function(context)
		for _, photo in pairs(photos) do
			photo:setPropertyForPlugin(_PLUGIN, INaturalistMetadata.ObservationUUID, uuid)
		end
	end)

end

import("LrTasks").startAsyncTask(groupObservation)