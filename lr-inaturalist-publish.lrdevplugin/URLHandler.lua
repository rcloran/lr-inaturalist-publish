local logger = import("LrLogger")("lr-inaturalist-publish")
local INaturalistAPI = require("INaturalistAPI")
local INaturalistUser = require("INaturalistUser")

return {
	URLHandler = function(url)
		logger:trace("URLHandler()")
		if url:find(INaturalistAPI.oauthRedirect, 1, true) == 1 then
			INaturalistUser.handleAuthRedirect(url)
		end
	end,
}
