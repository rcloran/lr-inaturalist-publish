local LrApplication = import("LrApplication")
local sha2 = require("sha2")

UUID = {}

-- Use the first 32 bits of a SHA256 hash as a random seed
function UUID.seed()
	local seed_s = sha2.sha256(LrApplication.macAddressHash() .. os.time() .. os.clock())
	seed_s = sha2.hex_to_bin(seed_s)

	local seed = 0
	for i = 1, 4 do
		seed = (seed * 256) + string.byte(seed_s:sub(i, i))
	end

	math.randomseed(seed % 2 ^ 31) -- Lua 5.1 only allows 31-bit here
end

function UUID.uuid4()
	-- Some segments broken up into two parts to avoid getting to/over
	-- 2^32, which would overflow the unsigned int to which these are cast
	-- (see rand(3)).
	return string.format(
		"%04x%04x-%04x-4%03x-%04x-%06x%06x",
		math.random(2 ^ 16) - 1,
		math.random(2 ^ 16) - 1,
		math.random(2 ^ 16) - 1,
		math.random(2 ^ 12) - 1,
		math.random(2 ^ 14) - 1 + 2 ^ 15,
		math.random(2 ^ 24) - 1,
		math.random(2 ^ 24) - 1
	)
end

return UUID
