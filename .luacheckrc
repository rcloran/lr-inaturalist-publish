std = "lightroom"

-- I can't find a better way to remove some stuff down the tree
stds.lightroom = {
	read_globals = {
		"LOC",
		"MAC_ENV",
		"WIN_ENV",
		"_PLUGIN",
		"import",
		-- Undocumented stuff
		"DEBUG",
		"NDEBUG",
		"RELEASE_BUILD",
		"_env",
		"pack", -- O_o
	},
}
for k, v in pairs(stds.lua51.read_globals) do
	if type(k) == "number" then
		error()
	end
	stds.lightroom.read_globals[k] = v
end
stds.lightroom.read_globals.os = { fields = { "clock", "date", "time", "tmpname" } }
-- table.getn/setn/maxn are deprecated in 5.1, so not part of what we copied
stds.lightroom.read_globals.coroutine = { fields = { "canYield", "running" } }
stds.lightroom.read_globals.debug = { fields = { "getInfo" } }

-- Can't put _VERSION in not_globals because it is in the Info.lua environment
stds.lightroom.read_globals._VERSION = nil

not_globals = {
	"collectgarbage",
	"gcinfo", -- Deprecated, so not in Lua 5.1 anyways
	"getfenv",
	"module",
	"newproxy",
	"package",
	"setfenv",
	-- Stuff not documented in Chapter 1:
	"print",
	"xpcall",
}

stds.lightroom_plugin_info = {
	-- A more limited environment for plugin info
	read_globals = {
		"LOC",
		"MAC_ENV",
		"WIN_ENV",
		"_VERSION",
		string = stds.lightroom.read_globals.string,
	},
}

files["*/Info.lua"].std = "lightroom_plugin_info"

-- Vendored files that we don't expect to maintain
files["*/sha2.lua"].ignore = { "." }
files["*/json.lua"].ignore = { "." }
