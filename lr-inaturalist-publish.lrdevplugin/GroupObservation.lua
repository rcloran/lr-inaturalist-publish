local LrApplication = import("LrApplication")
local LrDialogs = import("LrDialogs")

local INaturalistMetadata = require("INaturalistMetadata")
local Random = require("Random")

-- Group photos into an observation. That is, assign observation UUIDs.
local function groupObservation()
	local catalog = LrApplication.activeCatalog()
	local photos = catalog:getTargetPhotos()

	if #photos <= 1 then
		LrDialogs.message("Please select more than 1 photo to group")
		return
	end

	local uuid, url = nil, nil
	for _, photo in pairs(photos) do
		local thisUUID = photo:getPropertyForPlugin(_PLUGIN, INaturalistMetadata.ObservationUUID)
		local thisURL = photo:getPropertyForPlugin(_PLUGIN, INaturalistMetadata.ObservationURL)
		if thisUUID and #thisUUID > 0 then
			if uuid ~= nil and uuid ~= thisUUID then
				LrDialogs.message(
					"Conflicting observations",
					"Two photos in the selection already belong to different observations"
				)
				return
			end
			uuid = thisUUID
			if thisURL and #thisURL > 0 then
				url = thisURL
			end
		end
	end

	if uuid == nil then
		uuid = Random.uuid4()
	end

	catalog:withWriteAccessDo("Group into observation", function(_)
		for _, photo in pairs(photos) do
			photo:setPropertyForPlugin(_PLUGIN, INaturalistMetadata.ObservationUUID, uuid)
			photo:setPropertyForPlugin(_PLUGIN, INaturalistMetadata.ObservationURL, url)
		end
		local msg = "Grouped %s photos into 1 observation"
		LrDialogs.showBezel(string.format(msg, #photos))
	end)
end

import("LrTasks").startAsyncTask(groupObservation)
