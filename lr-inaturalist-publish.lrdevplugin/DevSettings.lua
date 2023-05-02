local LrFileUtils = import("LrFileUtils")
local LrPathUtils = import("LrPathUtils")

local JSON = require("JSON")

local home = LrPathUtils.getStandardFilePath("home")
local f = LrPathUtils.child(home, ".lr-inaturalist-publish.json")

if not LrFileUtils.isReadable(f) then
	return {}
end

local v = JSON:decode(LrFileUtils.readFile(f))

if type(v) ~= "table" then
	return {}
end

return v
