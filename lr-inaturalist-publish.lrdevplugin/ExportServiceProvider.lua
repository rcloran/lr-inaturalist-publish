local LrApplication = import("LrApplication")
local LrDialogs = import("LrDialogs")
local LrHttp = import("LrHttp")
local LrTasks = import("LrTasks")
local LrView = import("LrView")

local bind = LrView.bind

local Login = require("Login")
local SyncObservations = require("SyncObservations")
local Upload = require("Upload")

local exportServiceProvider = {
	supportsIncrementalPublish = "only",
	exportPresetFields = {
		{ key = "login", default = "" },
		{ key = "syncKeywords", default = true },
		{ key = "syncKeywordsCommon", default = true },
		{ key = "syncKeywordsSynonym", default = true },
		{ key = "syncKeywordsIncludeOnExport", default = true },
		{ key = "syncKeywordsRoot", default = -1 },
		{ key = "syncOnPublish", default = true },
		{ key = "syncSearchIn", default = -1 },
		{ key = "syncTitle", default = false },
		{ key = "uploadKeywordsSpeciesGuess", default = true },
		{ key = "uploadPrivateLocation", default = "obscured" },
	},
	hideSections = {
		"exportLocation",
		"fileNaming",
	},
	allowFileFormats = { "JPEG" },
	-- Not sure if support for more color spaces exists. Keep UI simple
	-- for now...
	allowColorSpaces = { "sRGB" },
	hidePrintResolution = true,
	canExportVideo = false,
	-- Publish provider options
	small_icon = "Resources/inaturalist-icon.png",
	titleForGoToPublishedCollection = "Go to observations in iNaturalist",
}

-- called when the user picks this service in the publish dialog
function exportServiceProvider.startDialog(propertyTable)
	propertyTable:addObserver("login", function()
		Login.verifyLogin(propertyTable)
	end)
	Login.verifyLogin(propertyTable)
end

local function getCollectionsForPopup(parent, indent)
	local r = {}
	local children = parent:getChildCollections()
	for i = 1, #children do
		if not children[i]:isSmartCollection() then
			r[#r + 1] = {
				title = indent .. children[i]:getName(),
				value = children[i].localIdentifier,
			}
		end
	end

	children = parent:getChildCollectionSets()
	for i = 1, #children do
		local childrenItems = getCollectionsForPopup(children[i], indent .. "  ")
		if #childrenItems > 0 then
			r[#r + 1] = {
				title = indent .. children[i]:getName(),
				value = children[i].localIdentifier,
			}
			for j = 1, #childrenItems do
				r[#r + 1] = childrenItems[j]
			end
		end
	end

	return r
end

function exportServiceProvider.sectionsForTopOfDialog(f, propertyTable)
	local catalog = LrApplication.activeCatalog()
	LrTasks.startAsyncTask(function()
		local r = { {
			title = "--",
			value = -1,
		} }
		local items = getCollectionsForPopup(catalog, "")
		for i = 1, #items do
			r[#r + 1] = items[i]
		end
		propertyTable.syncSearchInItems = r
	end)

	LrTasks.startAsyncTask(function()
		local r = { { title = "--", value = -1 } }
		local kw = catalog:getKeywords()
		for i = 1, #kw do
			r[#r + 1] = {
				title = kw[i]:getName(),
				value = kw[i].localIdentifier,
			}
		end
		propertyTable.syncKeywordsRootItems = r
	end)

	local account = {
		title = "iNaturalist Account",
		synopsis = bind("accountStatus"),
		f:row({
			spacing = f:control_spacing(),
			f:static_text({
				title = bind("accountStatus"),
				alignment = "right",
				fill_horizontal = 1,
			}),
			f:push_button({
				title = bind("loginButtonTitle"),
				enabled = bind("loginButtonEnabled"),
				action = function()
					Login.login(propertyTable)
				end,
			}),
		}),
	}
	local options = {
		title = "Export options",
		f:row({
			spacing = f:control_spacing(),
			f:static_text({
				title = bind({
					keys = { "syncKeywordsRoot", "syncKeywordsRootItems" },
					transform = function(value, fromModel)
						if not fromModel then
							return value
						end -- shouldn't happen
						value = propertyTable.syncKeywordsRoot
						for _, item in pairs(propertyTable.syncKeywordsRootItems) do
							if item.value == value then
								value = item.title
							end
						end
						return 'Set species guess from keywords within "'
							.. value
							.. '" keyword\n'
							.. '(The setting for which keyword is in the "Synchronization" section)'
					end,
				}),
				alignment = "right",
				height_in_lines = 2,
				width = LrView.share("inaturalistSyncLabel"),
			}),
			f:checkbox({
				value = bind("uploadKeywordsSpeciesGuess"),
				enabled = bind({
					key = "syncKeywordsRoot",
					transform = function(value, fromModel)
						if not fromModel then
							return value
						end -- shouldn't happen
						if value and value ~= -1 then
							return true
						end
						return false
					end,
				}),
				alignment = "left",
			}),
		}),
		f:row({
			spacing = f:control_spacing(),
			f:static_text({
				title = "Set observation location for photos in LR private locations",
				alignment = "right",
				width = LrView.share("inaturalistSyncLabel"),
			}),
			f:popup_menu({
				value = bind("uploadPrivateLocation"),
				items = {
					{ title = "Public", value = "public" },
					{ title = "Obscured", value = "obscured" },
					{ title = "Private", value = "private" },
					{ title = "Don't set", value = "unset" },
				},
			}),
		}),
	}
	local synchronization = {
		title = "iNaturalist Synchronization",
		f:row({
			spacing = f:control_spacing(),
			f:static_text({
				title = "These options control how changes on iNaturalist are synchronized into your catalog.",
				height_in_lines = -1,
				fill_horizontal = 1,
			}),
		}),
		f:row({
			f:static_text({
				title = "Help...",
				width_in_chars = 0,
				alignment = "right",
				text_color = import("LrColor")(0, 0, 1),
				mouse_down = function()
					LrHttp.openUrlInBrowser("https://github.com/rcloran/lr-inaturalist-publish/wiki/Synchronization")
				end,
			}),
		}),
		f:row({
			spacing = f:control_spacing(),
			f:static_text({
				title = "Only search for photos to sync from iNaturalist in",
				alignment = "right",
				width = LrView.share("inaturalistSyncLabel"),
			}),
			f:popup_menu({
				value = bind("syncSearchIn"),
				items = bind("syncSearchInItems"),
			}),
		}),
		f:row({
			spacing = f:control_spacing(),
			f:static_text({
				title = "Synchronize from iNaturalist during every publish",
				alignment = "right",
				width = LrView.share("inaturalistSyncLabel"),
			}),
			f:checkbox({
				value = bind("syncOnPublish"),
			}),
		}),
		f:row({
			spacing = f:control_spacing(),
			f:static_text({
				title = "Update keywords from iNaturalist data",
				alignment = "right",
				width = LrView.share("inaturalistSyncLabel"),
			}),
			f:checkbox({
				value = bind("syncKeywords"),
			}),
		}),
		f:row({
			spacing = f:control_spacing(),
			f:static_text({
				title = "Use common names for keywords",
				alignment = "right",
				width = LrView.share("inaturalistSyncLabel"),
				enabled = bind("syncKeywords"),
			}),
			f:checkbox({
				value = bind("syncKeywordsCommon"),
				enabled = bind("syncKeywords"),
			}),
		}),
		f:row({
			spacing = f:control_spacing(),
			f:static_text({
				title = bind({
					keys = { "syncKeywordsCommon" },
					transform = function()
						local r = "Set common name as a keyword synonym"
						if propertyTable.syncKeywordsCommon then
							r = "Set scientific name as a keyword synonym"
						end
						r = r .. '\nKeyword synonyms are always exported (see "Help...")'
						return r
					end,
				}),
				alignment = "right",
				width = LrView.share("inaturalistSyncLabel"),
				enabled = bind("syncKeywords"),
			}),
			f:checkbox({
				value = bind("syncKeywordsSynonym"),
				enabled = bind("syncKeywords"),
			}),
		}),
		f:row({
			spacing = f:control_spacing(),
			f:static_text({
				title = 'Set "Include on Export" attribute on keywords',
				alignment = "right",
				width = LrView.share("inaturalistSyncLabel"),
				enabled = bind("syncKeywords"),
			}),
			f:checkbox({
				value = bind("syncKeywordsIncludeOnExport"),
				enabled = bind("syncKeywords"),
			}),
		}),
		f:row({
			spacing = f:control_spacing(),
			f:static_text({
				title = "Put keywords within this keyword:\n"
					.. "Note: If this isn't set, keywords can't be properly changed (see \"Help...\")",
				alignment = "right",
				width = LrView.share("inaturalistSyncLabel"),
				enabled = bind("syncKeywords"),
			}),
			f:popup_menu({
				value = bind("syncKeywordsRoot"),
				items = bind("syncKeywordsRootItems"),
				enabled = bind("syncKeywords"),
			}),
		}),
		f:row({
			spacing = f:control_spacing(),
			f:static_text({
				title = "Set title to observation identification",
				alignment = "right",
				width = LrView.share("inaturalistSyncLabel"),
			}),
			f:checkbox({
				value = bind("syncTitle"),
			}),
		}),
		f:separator({ fill_horizontal = 1 }),
		f:row({
			spacing = f:control_spacing(),
			f:static_text({
				title = "Synchronize everything from iNaturalist, even if it might not have changed:",
				height_in_lines = -1,
				alignment = "right",
				width = LrView.share("inaturalistSyncLabel"),
				enabled = bind("LR_editingExistingPublishConnection"),
			}),
			f:push_button({
				title = "Full synchronization now",
				action = function()
					LrTasks.startAsyncTask(function()
						SyncObservations.fullSync(propertyTable)
					end)
				end,
				enabled = bind("LR_editingExistingPublishConnection"),
			}),
		}),
		f:row({
			spacing = f:control_spacing(),
			f:static_text({
				title = "Synchronize changes since last sync:",
				height_in_lines = -1,
				alignment = "right",
				width = LrView.share("inaturalistSyncLabel"),
				enabled = bind("LR_editingExistingPublishConnection"),
			}),
			f:push_button({
				title = "Synchronize now",
				action = function()
					LrTasks.startAsyncTask(function()
						SyncObservations.sync(propertyTable)
					end)
				end,
				enabled = bind("LR_editingExistingPublishConnection"),
			}),
		}),
	}

	return { account, options, synchronization }
end

function exportServiceProvider.processRenderedPhotos(...)
	return Upload.processRenderedPhotos(...)
end

-- Publish provider functions
function exportServiceProvider.metadataThatTriggersRepublish(publishSettings)
	local r = {
		default = false,
		caption = true,
		dateCreated = true,
		gps = true,
		keywords = publishSettings.uploadKeywords,
	}

	return r
end

function exportServiceProvider.deletePhotosFromPublishedCollection(...)
	return Upload.deletePhotosFromPublishedCollection(...)
end

function exportServiceProvider.getCollectionBehaviorInfo(_)
	return {
		defaultCollectionName = "Observations",
		defaultCollectionCanBeDeleted = false,
		canAddCollection = false,
		maxCollectionSetDepth = 0,
	}
end

function exportServiceProvider.goToPublishedCollection(publishSettings, _)
	LrHttp.openUrlInBrowser("https://www.inaturalist.org/observations/" .. publishSettings.login)
end

function exportServiceProvider.didCreateNewPublishService(publishSettings, info)
	-- Emulates the setup we have when editing config
	publishSettings.LR_publishService = info.publishService

	local f = LrView.osFactory()
	local mainMsg = "This will take some time."
	if publishSettings.syncOnPublish then
		mainMsg = "This will take some time. If you do not do this now it will happen "
			.. "automatically the first time you publish using this plugin."
	end
	local c = {
		spacing = f:dialog_spacing(),
		f:static_text({
			title = mainMsg,
			fill_horizontal = 1,
			width_in_chars = 50,
			height_in_lines = 2,
		}),
	}
	if publishSettings.syncSearchIn == -1 then
		c[#c + 1] = f:static_text({
			title = "You have not set a collection to which to limit the search "
				.. "for matching photos. This may result in a low number of matches.",
			fill_horizontal = 1,
			width_in_chars = 50,
			height_in_lines = 2,
		})
	end
	local r = LrDialogs.presentModalDialog({
		title = "Perform synchronization from iNaturalist now?",
		contents = f:column(c),
	})

	if r == "ok" then
		SyncObservations.fullSync(publishSettings)
	end
end

-- function exportServiceProvider.canAddCommentsToService(publishSettings)
-- return INaturalistAPI.testConnection(publishSettings)
-- end
--

return exportServiceProvider
