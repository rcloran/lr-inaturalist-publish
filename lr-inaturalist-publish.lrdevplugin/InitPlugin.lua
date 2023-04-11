local logger = import("LrLogger")("lr-inaturalist-publish")

local prefs = import("LrPrefs").prefsForPlugin()

local function configureLogging(_, _, value)
	logger:disable()
	if value == "trace" then
		logger:enable("logfile")
		logger:info("Enabled trace logging")
	end
end

prefs:addObserver("logLevel", configureLogging)
configureLogging(prefs, "logLevel", prefs.logLevel)
logger:trace("------------------ Starting iNaturalist Publish Service Plugin")

require("UUID") -- Set up UUID/randomness
