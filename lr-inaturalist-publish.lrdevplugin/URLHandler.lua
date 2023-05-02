local logger = import("LrLogger")("lr-inaturalist-publish")
local INaturalistAPI = require("INaturalistAPI")
local Login = require("Login")

return {
	URLHandler = function(url)
		logger:trace("URLHandler()")
		if url:find(INaturalistAPI.oauthRedirect, 1, true) == 1 then
			Login.handleAuthRedirect(url)
		end
	end,
}
