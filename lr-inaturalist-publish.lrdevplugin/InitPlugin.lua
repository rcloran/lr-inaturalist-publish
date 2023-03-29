local logger = import("LrLogger")("lr-inaturalist-publish")

local Prefs = require("Prefs")

if Prefs.trace then
	logger:enable("logfile")
	logger:trace("------------------ Starting iNaturalist Publish Service")
end

_VERSION = "Lua 5.1" -- sha2 needs _VERSION

local UUID = require("UUID")
-- Seed math.randomseed() with something good^Wpassable^Wbetter than just os.time()
UUID.seed()
