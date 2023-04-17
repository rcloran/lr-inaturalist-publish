local prefs = import("LrPrefs").prefsForPlugin()
local LrView = import("LrView")

local Updates = require("Updates")

local bind = LrView.bind

local Info = {}

function Info.sectionsForTopOfDialog(f, _)
	if prefs.checkForUpdates == nil then
		prefs.checkForUpdates = true
	end
	local settings = {
		title = "Plugin options",
		bind_to_object = prefs,

		f:row({
			f:static_text({
				title = "Automatically check for updates",
				alignment = "right",
				width = LrView.share("inaturalistPrefsLabel"),
			}),
			f:checkbox({
				value = bind("checkForUpdates"),
				alignment = "left",
			}),
		}),

		f:row({
			f:static_text({
				title = "Check for updates now",
				alignment = "right",
				width = LrView.share("inaturalistPrefsLabel"),
			}),
			f:push_button({
				title = "Go",
				action = Updates.forceUpdate,
			}),
		}),

		f:row({
			f:static_text({
				title = "Log level",
				alignment = "right",
				width = LrView.share("inaturalistPrefsLabel"),
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
