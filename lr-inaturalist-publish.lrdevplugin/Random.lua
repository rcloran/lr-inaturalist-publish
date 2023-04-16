local LrApplication = import("LrApplication")
local sha2 = require("sha2")

local Random = {}

-- Use the first 32 bits of a SHA256 hash as a random seed. Hash some
-- slightly unique and unpredictable (hopefully) data for that. The result is
-- still not good.
function Random.seed()
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

function Random.uuid4()
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

function Random.rand256()
	-- 256 bits (32 bytes) of random
	local s = ""
	for _ = 1, 32 do
		s = s .. string.char(math.random(0, 255))
	end
	return s
end

local urandom = io.open("/dev/urandom", "rb")
if urandom then
	-- If we have access to a high quality source of randomness, then use that
	-- by installing a better function.
	Random.uuid4 = function()
		local b = urandom:read(16)
		-- High nibble of version = 0100
		local version = string.char(64 + string.byte(b:sub(7, 7)) % 16)
		-- High two bits of variant = 10
		local variant = string.char(128 + string.byte(b:sub(9, 9)) % 64)

		b = sha2.bin_to_hex(b:sub(1, 4))
			.. "-"
			.. sha2.bin_to_hex(b:sub(5, 6))
			.. "-"
			.. sha2.bin_to_hex(version .. b:sub(8, 8))
			.. "-"
			.. sha2.bin_to_hex(variant .. b:sub(10, 10))
			.. "-"
			.. sha2.bin_to_hex(b:sub(11, 16))

		return b
	end

	Random.rand256 = function()
		return urandom:read(32)
	end
else
	Random.seed()
end

return Random
