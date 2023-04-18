-- Get random bits by using the uuid.vbs helper (Windows)
local LrFileUtils = import("LrFileUtils")
local LrMath = import("LrMath")
local LrPathUtils = import("LrPathUtils")
local LrTasks = import("LrTasks")

local RandomLua = require("RandomLua")
local sha2 = require("sha2")

local RandomWin = {}

local cache = {}

local function isUUID(s)
	local start, len = s:find("^%x+-%x+-%x+-%x+-%x+")
	if not (start == 1 and len == 36) then
		return false
	end
	return true
end

local function execWithOutput(cmd)
	-- io.popen() unfortunately pops up a Command Prompt window, which makes
	-- LrTasks.execute much more appealing. But that means that we have to get
	-- output through a temporary file and be in an async context, urgh.
	local tmp = os.tmpname()
	local status = LrTasks.execute(cmd .. ' > "' .. tmp .. '"')
	if status ~= 0 then
		LrFileUtils.delete(tmp)
		return ""
	end
	local f = io.open(tmp, "rb")
	local output = f:read("*a")
	if not output then
		f:close()
		return ""
	end
	f:close()
	LrFileUtils.delete(tmp)
	return output
end

local function getUUIDs()
	local vbs = LrPathUtils.child(_PLUGIN.path, "uuid.vbs")
	local output = execWithOutput('cscript /NoLogo "' .. vbs .. '"')
	for line in output:gmatch("([^\n]+)\n") do
		if not isUUID(line) then
			return false
		end
		table.insert(cache, line)
	end
	return true
end

function RandomWin.available()
	return getUUIDs()
end

function RandomWin.uuid4()
	if #cache == 0 then
		getUUIDs(cache)
	end
	return table.remove(cache):lower()
end

local function uuid2hex(uuid)
	-- remove -, and also two nibbles from the UUID which should be the
	-- version, and a nibble that includes the variant.
	return uuid:gsub("(.+)-(.+)-4(.+)-.(.+)-(.+)", "%1%2%3%4%5")
end

function RandomWin.rand256()
	if #cache < 3 then
		getUUIDs(cache)
	end
	local s = ""
	for _ = 1, 3 do
		s = s .. uuid2hex(table.remove(cache):lower())
	end

	-- The result of this function are used as secrets for login, but since it
	-- has to go through a file, it is interceptable. Combination of two
	-- independent random sources with xor is random, and doing so might make
	-- things a little harder to intercept/predict. Probably overkill.
	local myRandom = sha2.hex_to_bin(s):sub(1, 32)
	local luaRandom = RandomLua.rand256()
	local r = {}

	for i = 1, #myRandom do
		local asInt = LrMath.bitXor(myRandom:sub(i, i):byte(), luaRandom:sub(i, i):byte())
		table.insert(r, string.char(asInt))
	end
	return table.concat(r)
end

function RandomWin.seed()
	RandomLua.seed()
end

return RandomWin
