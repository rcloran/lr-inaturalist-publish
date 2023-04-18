-- Get random bits by reading from /dev/urandom (macOS)

local sha2 = require("sha2")

local RandomMac = {}

local urandom = io.open("/dev/urandom", "rb")

function RandomMac.available()
	return urandom ~= nil
end

function RandomMac.uuid4()
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

function RandomMac.rand256()
	return urandom:read(32)
end

function RandomMac.seed()
	return
end

return RandomMac
