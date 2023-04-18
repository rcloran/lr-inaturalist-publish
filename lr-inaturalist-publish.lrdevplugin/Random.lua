local logger = import("LrLogger")("lr-inaturalist-publish")

local Random = {}

local options = { "RandomMac", "RandomWin", "RandomLua" }

-- Instead of just choosing with some file-level code and returning the chosen
-- implementation from this file, functions are swapped in when the actual
-- random functions are called, because the Windows implementation only works
-- when it's run from an async context.
local function chooseImpl()
	for _, mod in ipairs(options) do
		local impl = require(mod)
		if impl.available() then
			logger:debugf("Selected %s as Random implementation", mod)
			impl.seed()
			Random.uuid4 = impl.uuid4
			Random.rand256 = impl.rand256
			return impl
		end
	end
end

function Random.uuid4()
	local impl = chooseImpl()
	return impl.uuid4()
end
function Random.rand256()
	local impl = chooseImpl()
	return impl.rand256()
end

return Random
