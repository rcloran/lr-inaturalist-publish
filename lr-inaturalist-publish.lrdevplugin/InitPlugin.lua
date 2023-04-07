local logger = import("LrLogger")("lr-inaturalist-publish")

local prefs = import("LrPrefs").prefsForPlugin()

local function configureLogging(prefs, _, value)
	logger:disable()
	if value == "trace" then
		logger:enable("logfile")
		logger:info("Enabled trace logging")
	end
end

prefs:addObserver("logLevel", configureLogging)
configureLogging(prefs, _, prefs.logLevel)
logger:trace("------------------ Starting iNaturalist Publish Service Plugin")

_VERSION = "Lua 5.1" -- sha2 needs _VERSION

local UUID = require("UUID") -- Set up UUID/randomness
