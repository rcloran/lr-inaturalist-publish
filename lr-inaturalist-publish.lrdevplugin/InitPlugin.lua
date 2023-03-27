local logger = import "LrLogger"("lr-inaturalist-publish")

local Prefs = require("Prefs")

if Prefs.trace then
	logger:enable("logfile")
	logger:trace("------------------------ Starting iNaturalist Publish Service")
end

local LrApplication = import("LrApplication")
_VERSION = LrApplication.versionTable()  -- Not available globally otherwise
