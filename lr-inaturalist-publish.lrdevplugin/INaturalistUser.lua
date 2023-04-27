local logger = import("LrLogger")("lr-inaturalist-publish")
local LrDialogs = import("LrDialogs")
local LrHttp = import("LrHttp")
local LrPasswords = import("LrPasswords")
local LrTasks = import("LrTasks")

local INaturalistAPI = require("INaturalistAPI")
local JSON = require("JSON")
local Random = require("Random")
local sha2 = require("sha2")

local INaturalistUser = {}

function INaturalistUser.verifyLogin(propertyTable)
	if propertyTable.login and #propertyTable.login > 0 then
		propertyTable.accountStatus = "Logged in as " .. propertyTable.login
		propertyTable.loginButtonTitle = "Log out"
		propertyTable.loginButtonEnabled = false
	else
		propertyTable.accountStatus = "Not logged in"
		propertyTable.loginButtonTitle = "Log in"
		propertyTable.loginButtonEnabled = true
		propertyTable.api = nil
	end
end

local function base64urlencode(s)
	s = sha2.bin_to_base64(s)
	s = string.gsub(s, "=", "")
	s = string.gsub(s, "+", "-")
	s = string.gsub(s, "/", "_")
	return s
end

local function generateSecret()
	return base64urlencode(Random.rand256())
end

function INaturalistUser.login(propertyTable)
	logger:trace("INaturalistUser.login()")
	local baseUrl = "https://www.inaturalist.org/oauth/authorize"
	local challenge = generateSecret()
	local code_challenge = base64urlencode(sha2.hex_to_bin(sha2.sha256(challenge)))

	local url = string.format(
		"%s?client_id=%s&code_challenge=%s&code_challenge_method=S256&redirect_uri=%s&response_type=code",
		baseUrl,
		INaturalistAPI.clientId,
		code_challenge,
		INaturalistAPI.urlencode(INaturalistAPI.oauthRedirect)
	)
	propertyTable.pkceChallenge = challenge
	INaturalistUser.inProgressLogin = propertyTable
	LrHttp.openUrlInBrowser(url)
end

function INaturalistUser.handleAuthRedirect(url)
	logger:trace("handleAuthRedirect()")
	local params = {}
	for k, v in url:gmatch("([^&=?]-)=([^&=?]+)") do
		params[k] = v
	end

	if params["code"] then
		local propertyTable = INaturalistUser.inProgressLogin
		if not (propertyTable and propertyTable.pkceChallenge) then
			LrDialogs.message(
				"Unexpected iNaturalist login received",
				"No login is in progress. Leave the publishing manager open while authorizing with iNaturalist in your browser."
			)
			return
		end
		LrTasks.startAsyncTask(function()
			local accessToken = INaturalistUser.getToken(params["code"], propertyTable.pkceChallenge)
			propertyTable.pkceChallenge = nil
			local api = INaturalistAPI:new(nil, accessToken)
			local login = api:getUser().login
			LrPasswords.store(login, accessToken)
			propertyTable.login = login
			INaturalistUser.verifyLogin(propertyTable)
		end)
	end
end

-- Obtain an OAuth access token (second stage of OAuth)
function INaturalistUser.getToken(code, challenge)
	logger:trace("getToken()")
	assert(type(code) == "string")
	assert(type(challenge) == "string")
	local url = "https://www.inaturalist.org/oauth/token"
	local headers = { { field = "Content-Type", value = "application/x-www-form-urlencoded" } }
	local body = {
		code = code,
		client_id = INaturalistAPI.clientId,
		grant_type = "authorization_code",
		code_verifier = challenge,
		redirect_uri = INaturalistAPI.oauthRedirect,
	}
	body = INaturalistAPI.formEncode(body)
	local data, respHeaders = LrHttp.post(url, body, headers)
	if respHeaders.error then
		error(string.format("Error logging in: %s", headers.error.name))
	elseif respHeaders.status ~= 200 then
		error(string.format("iNaturalist API error: %s", data))
	end
	data = JSON:decode(data)
	return data.access_token
end

return INaturalistUser
