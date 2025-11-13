local logger = import("LrLogger")("lr-inaturalist-publish")
local prefs = import("LrPrefs").prefsForPlugin()
local LrDialogs = import("LrDialogs")
local LrFileUtils = import("LrFileUtils")
local LrFunctionContext = import("LrFunctionContext")
local LrPathUtils = import("LrPathUtils")
local LrHttp = import("LrHttp")
local LrTasks = import("LrTasks")

local Info = require("Info")
local json = require("dkjson")

local Updates = {
	baseUrl = "https://api.github.com/",
	repo = "rcloran/lr-inaturalist-publish",
	actionPrefKey = "doNotShowUpdatePrompt",
}

local function getLatestVersion()
	local url = Updates.baseUrl .. "repos/" .. Updates.repo .. "/releases/latest"
	local headers = {
		{ field = "User-Agent", value = Updates.repo .. "/" .. Updates.version() },
		{ field = "X-GitHub-Api-Version", value = "2022-11-28" },
	}
	local data, respHeaders = LrHttp.get(url, headers)

	if respHeaders.error or respHeaders.status ~= 200 then
		return
	end

	local success, release = pcall(json.decode, data)
	if not success then
		return
	end

	logger:tracef("Found latest release: %s", release.tag_name)
	return release
end

local function shellquote(s)
	-- Quote a file name so it's ready to concat into a command
	if MAC_ENV then
		s = s:gsub("'", "'\\''")
		return "'" .. s .. "'"
	else -- WIN_ENV
		-- Double quotes are not allowed in file names, so take the easy path
		return '"' .. s .. '"'
	end
end

local function download(release, filename)
	local data, headers = LrHttp.get(release.assets[1].browser_download_url)
	if headers.error then
		return false
	end

	if LrFileUtils.exists(filename) and not LrFileUtils.isWritable(filename) then
		error(LOC("$$$/iNat/Updates/CannotWriteFile=Cannot write to download file"))
	end

	local f = io.open(filename, "wb")
	f:write(data)
	f:close()
end

local function extract(filename, workdir)
	local cmd = "tar -C " .. shellquote(workdir) .. " -xf " .. shellquote(filename)
	logger:trace(cmd)
	local ret = LrTasks.execute(cmd)
	if ret ~= 0 then
		error(LOC("$$$/iNat/Updates/CannotExtract=Could not extract downloaded release file"))
	end
end

local function install(workdir, pluginPath)
	local newPluginPath = nil
	for path in LrFileUtils.directoryEntries(workdir) do
		if path:find("%.lrplugin$") then
			newPluginPath = path
		end
	end
	local scratch = LrFileUtils.chooseUniqueFileName(newPluginPath)
	LrFileUtils.move(pluginPath, scratch)
	LrFileUtils.move(newPluginPath, pluginPath)
	-- Don't need to delete scratch, since workdir cleanup will
end

local function downloadAndInstall(ctx, release)
	-- Work in sibling to the plugin folder so that moves are just renames
	local workdir = LrFileUtils.chooseUniqueFileName(_PLUGIN.path)
	ctx:addCleanupHandler(function()
		LrFileUtils.delete(workdir)
	end)
	local r = LrFileUtils.createDirectory(workdir)
	if not r then
		error(LOC("$$$/iNat/Updates/CannotCreateDir=Cannot create temporary directory"))
	end
	local zip = LrPathUtils.child(workdir, "download.zip")

	download(release, zip)
	extract(zip, workdir)
	install(workdir, _PLUGIN.path)
end

local function showUpdateDialog(release, force)
	if release.tag_name ~= prefs.lastUpdateOffered then
		LrDialogs.resetDoNotShowFlag(Updates.actionPrefKey)
		prefs.lastUpdateOffered = release.tag_name
	end

	local info = LOC(
		"$$$/iNat/Updates/UpdateAvailableInfo=An update is available for the iNaturalist Publish Plugin. "
			.. "Would you like to download it now?"
	)
	if release.body and #release.body > 0 then
		info = info .. "\n\n" .. release.body
	end

	local actionPrefKey = Updates.actionPrefKey
	if force then
		actionPrefKey = nil
	end

	local toDo = LrDialogs.promptForActionWithDoNotShow({
		message = LOC("$$$/iNat/Updates/UpdateAvailableTitle=iNaturalist Publish Plugin update available"),
		info = info,
		actionPrefKey = actionPrefKey,
		verbBtns = {
			{ label = LOC("$$$/iNat/Updates/DownloadButton=Download"), verb = "download" },
			{ label = LOC("$$$/iNat/Updates/IgnoreButton=Ignore"), verb = "ignore" },
		},
	})
	if toDo == "download" then
		if #release.assets ~= 1 then
			-- Unexpected. Open a browser window to the release page.
			LrHttp.openUrlInBrowser(release.html_url)
			return
		end

		if LrTasks.execute("tar --help") == 0 then
			LrFunctionContext.callWithContext("downloadAndInstall", downloadAndInstall, release)
			LrDialogs.message(
				LOC("$$$/iNat/Updates/UpdateInstalledTitle=iNaturalist Publish Plugin update installed"),
				LOC("$$$/iNat/Updates/UpdateInstalledInfo=Please restart Lightroom"),
				"info"
			)
		else
			-- We need the user to download and extract the zip file
			LrHttp.openUrlInBrowser(release.assets[1].browser_download_url)
		end
	else
		logger:tracef("Update dialog response: %s", toDo)
	end
end

function Updates.version()
	local v = Info.VERSION
	return string.format("%s.%s.%s", v.major, v.minor, v.revision)
end

function Updates.check(force)
	-- Returns the current version as a string if no update is available, or
	-- nil if an update dialog was shown.

	-- Always log the current version
	local current = "v" .. Updates.version()
	logger:debugf("Running %s", Info.VERSION.display or current)

	if not force and not prefs.checkForUpdates then
		return
	end

	local latest = getLatestVersion()
	if not latest then
		return
	end

	if current ~= latest.tag_name then
		logger:tracef("Offering update from %s to %s", current, latest.tag_name)
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
				LOC("$$$/iNat/Updates/NoUpdatesTitle=No updates available"),
				LOC(
					"$$$/iNat/Updates/NoUpdatesInfo=You have the most recent version of the iNaturalist "
						.. "Publish Plugin, ^1",
					v
				),
				"info"
			)
		end
	end)
end

return Updates
