-- Get random bits using Lua's built-in math.random. Intended as a fallback in
-- case we can't make the macOS or Windows specific versions work.

local LrApplication = import("LrApplication")

local sha2 = require("sha2")

local RandomLua = {}

function RandomLua.available()
	return true
end

-- Use the first 32 bits of a SHA256 hash as a random seed. Hash some
-- slightly unique and unpredictable (hopefully) data for that. The result is
-- still not good.
function RandomLua.seed()
	local seed_s = LrApplication.macAddressHash() .. os.time() .. os.clock()
	-- Perhaps something unpredictable in memory addresses of globals. ¯\_(ツ)_/¯
	for _, v in pairs(_G) do
		seed_s = seed_s .. tostring(v)
	end
	seed_s = sha2.hex_to_bin(sha2.sha256(seed_s))

	local seed = 0
	for i = 1, 4 do
		seed = (seed * 256) + string.byte(seed_s:sub(i, i))
	end

	math.randomseed(seed % 2 ^ 31) -- Lua 5.1 only works properly with 31-bit here
end

function RandomLua.uuid4()
	-- Some segments broken up into two parts to avoid getting to/over
	-- 2^32, which would overflow the unsigned int to which these are cast
	-- (see rand(3)).
	return string.format(
		"%04x%04x-%04x-4%03x-%04x-%06x%06x",
		--             ^- version
		math.random(2 ^ 16) - 1,
		math.random(2 ^ 16) - 1,
		math.random(2 ^ 16) - 1,
		math.random(2 ^ 12) - 1,
		math.random(2 ^ 14) - 1 + 2 ^ 15, -- variant word has two high bits 10
		math.random(2 ^ 24) - 1,
		math.random(2 ^ 24) - 1
	)
end

function RandomLua.rand256()
	-- 256 bits (32 bytes) of random
	local s = ""
	for _ = 1, 32 do
		s = s .. string.char(math.random(0, 255))
	end
	return s
end

return RandomLua
