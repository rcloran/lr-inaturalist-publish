local prefs = import("LrPrefs").prefsForPlugin()
local LrDialogs = import("LrDialogs")
local LrHttp = import("LrHttp")
local LrTasks = import("LrTasks")

local Info = require("Info")
local JSON = require("JSON")

local Updates = {
	baseUrl = "https://api.github.com/",
	repo = "rcloran/lr-inaturalist-publish",
	actionPrefKey = "doNotShowUpdatePrompt",
}

local function getLatestVersion()
	local url = Updates.baseUrl .. "repos/" .. Updates.repo .. "/releases/latest"
	local headers = {
		{ field = "X-GitHub-Api-Version", value = "2022-11-28" },
	}
	local data, respHeaders = LrHttp.get(url, headers)

	if respHeaders.error or respHeaders.status ~= 200 then
		return
	end

	local success, release = pcall(function()
		return JSON:decode(data)
	end)
	if not success then
		return
	end

	return release
end

local function showUpdateDialog(release, force)
	if release.tag_name ~= prefs.lastUpdateOffered then
		LrDialogs.resetDoNotShowFlag(Updates.actionPrefKey)
		prefs.lastUpdateOffered = release.tag_name
	end

	local info = "An update is available for the iNaturalist Publish Plugin. Would you like to download it now?"
	if release.body and #release.body > 0 then
		info = info .. "\n\n" .. release.body
	end

	local actionPrefKey = Updates.actionPrefKey
	if force then
		actionPrefKey = nil
	end

	local toDo = LrDialogs.promptForActionWithDoNotShow({
		message = "iNaturalist Publish Plugin update available",
		info = info,
		actionPrefKey = actionPrefKey,
		verbBtns = {
			{ label = "Download", verb = "download" },
			{ label = "Ignore", verb = "ignore" },
		},
	})
	if toDo == "download" then
		if #release.assets ~= 1 then
			-- Unexpected. Open a browser window to the release page.
			LrHttp.openUrlInBrowser(release.html_url)
			return
		end

		LrHttp.openUrlInBrowser(release.assets[1].browser_download_url)
	end
end

function Updates.check(force)
	-- Returns the current version as a string if no update is available, or
	-- nil if an update dialog was shown.
	if not force and not prefs.checkForUpdates then
		return
	end

	local latest = getLatestVersion()
	if not latest then
		return
	end
	local v = Info.VERSION
	local current = string.format("v%s.%s.%s", v.major, v.minor, v.revision)

	if current ~= latest.tag_name then
		showUpdateDialog(latest, force)
		return
	end

	return current
end

function Updates.forceUpdate()
	LrTasks.startAsyncTask(function()
		local v = Updates.check(true)

		if v then
			LrDialogs.message(
				"No updates available",
				string.format("You have the most recent version of the iNaturalist Publish Plugin, %s", v)
			)
		end
	end)
end

return Updates
