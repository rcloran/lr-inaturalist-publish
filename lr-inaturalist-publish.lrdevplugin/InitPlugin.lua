local logger = import("LrLogger")("lr-inaturalist-publish")
local LrTasks = import("LrTasks")

local prefs = import("LrPrefs").prefsForPlugin()

local function configureLogging(_, _, value)
	logger:disable()
	if value == "trace" then
		logger:enable("logfile")
		logger:info("Enabled trace logging")
	end
end

LrTasks.startAsyncTask(function()
	prefs:addObserver("logLevel", configureLogging)
	configureLogging(prefs, "logLevel", prefs.logLevel)
	logger:trace("--------------- Starting iNaturalist Publish Service Plugin")

	require("Updates").check(false)
end)
