local logger = import("LrLogger")("lr-inaturalist-publish")
local prefs = import("LrPrefs").prefsForPlugin()
local LrView = import("LrView")

local bind = LrView.bind

local Info = {}

function Info.sectionsForTopOfDialog(f, propertyTable)
	local settings = {
		title = "Plugin options",
		bind_to_object = prefs,

		f:row({
			f:static_text({
				title = "Log level",
				alignment = "right",
				fill_horizontal = 1,
			}),
			f:popup_menu({
				value = bind("logLevel"),
				items = {
					{ title = "None", value = nil },
					{ title = "Trace", value = "trace" },
				},
			}),
		}),
	}

	return { settings }
end

return Info
