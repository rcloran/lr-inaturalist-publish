local LrApplication = import("LrApplication")
local LrDialogs = import("LrDialogs")
local LrHttp = import("LrHttp")
local LrTasks = import("LrTasks")
local LrView = import("LrView")

local bind = LrView.bind

local Login = require("Login")
local SyncObservations = require("SyncObservations")
local Upload = require("Upload")
local sha2 = require("sha2")

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
	titleForGoToPublishedCollection = LOC("$$$/iNat/Export/GoToPublished=Go to observations in iNaturalist"),
}

-- called when the user picks this service in the publish dialog
function exportServiceProvider.startDialog(propertyTable)
	if not propertyTable.LR_editingExistingPublishConnection then
		-- Start with empty login for new connections
		propertyTable.login = ""
	end
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
		title = LOC("$$$/iNat/Export/AccountTitle=iNaturalist Account"),
		synopsis = bind("accountStatus"),
		f:row({
			spacing = f:control_spacing(),
			f:static_text({
				title = bind("accountStatus"),
				alignment = "right",
				fill_horizontal = 1,
			}),
			f:push_button({
				title = LOC("$$$/iNat/Export/LogInButton=Log in"),
				enabled = bind("loginButtonEnabled"),
				action = function()
					LrTasks.startAsyncTask(function()
						Login.login(propertyTable)
					end)
				end,
			}),
		}),
	}
	local options = {
		title = LOC("$$$/iNat/Export/OptionsTitle=Export options"),
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
						return LOC(
							"$$$/iNat/Export/SpeciesGuessInfo=Set species guess from keywords within "
								.. '"^1" keyword\n(The setting for which keyword is in the '
								.. '"Synchronization" section)',
							value
						)
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
				title = LOC(
					"$$$/iNat/Export/PrivateLocationLabel=Set observation location for photos in LR "
						.. "private locations"
				),
				alignment = "right",
				width = LrView.share("inaturalistSyncLabel"),
			}),
			f:popup_menu({
				value = bind("uploadPrivateLocation"),
				items = {
					{ title = LOC("$$$/iNat/Export/LocationPublic=Public"), value = "public" },
					{ title = LOC("$$$/iNat/Export/LocationObscured=Obscured"), value = "obscured" },
					{ title = LOC("$$$/iNat/Export/LocationPrivate=Private"), value = "private" },
					{ title = LOC("$$$/iNat/Export/LocationUnset=Don't set"), value = "unset" },
				},
			}),
		}),
	}
	local synchronization = {
		title = LOC("$$$/iNat/Export/SyncTitle=iNaturalist Synchronization"),
		f:row({
			spacing = f:control_spacing(),
			f:static_text({
				title = LOC(
					"$$$/iNat/Export/SyncIntro=These options control how changes on iNaturalist are "
						.. "synchronized into your catalog."
				),
				height_in_lines = -1,
				fill_horizontal = 1,
			}),
		}),
		f:row({
			f:static_text({
				title = LOC("$$$/iNat/Export/HelpLink=Help..."),
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
				title = LOC("$$$/iNat/Export/SyncSearchLabel=Only search for photos to sync from iNaturalist in"),
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
				title = LOC("$$$/iNat/Export/SyncOnPublishLabel=Synchronize from iNaturalist during every publish"),
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
				title = LOC("$$$/iNat/Export/SyncKeywordsLabel=Update keywords from iNaturalist data"),
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
				title = LOC("$$$/iNat/Export/SyncCommonNamesLabel=Use common names for keywords"),
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
							r = LOC("$$/iNat/Export/SyncSynonymScientific=Set scientific name as a keyword synonym")
						end
						r = r
							.. "\n"
							.. LOC(
								"$$/iNat/Export/SyncSynonymNote=Keyword synonyms are always exported "
									.. '(see "Help...")'
							)
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
				title = LOC('$$/iNat/Export/SyncIncludeOnExportLabel=Set "Include on Export" attribute on keywords'),
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
				title = LOC(
					"$$$/iNat/Export/SyncKeywordsRootLabel=Put keywords within this keyword:\nNote: If this "
						.. "isn't set, keywords can't be properly changed (see \"Help...\")"
				),
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
				title = LOC("$$$/iNat/Export/SyncTitleLabel=Set title to observation identification"),
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
				title = LOC(
					"$$$/iNat/Export/FullSyncLabel=Synchronize everything from iNaturalist, even if it might "
						.. "not have changed:"
				),
				height_in_lines = -1,
				alignment = "right",
				width = LrView.share("inaturalistSyncLabel"),
				enabled = bind("LR_editingExistingPublishConnection"),
			}),
			f:push_button({
				title = LOC("$$$/iNat/Export/FullSyncButton=Full synchronization now"),
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
				title = LOC("$$$/iNat/Export/SyncNowLabel=Synchronize changes since last sync:"),
				height_in_lines = -1,
				alignment = "right",
				width = LrView.share("inaturalistSyncLabel"),
				enabled = bind("LR_editingExistingPublishConnection"),
			}),
			f:push_button({
				title = LOC("$$$/iNat/Export/SyncNowButton=Synchronize now"),
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
		defaultCollectionName = LOC("$$$/iNat/Export/DefaultCollectionName=Observations"),
		defaultCollectionCanBeDeleted = false,
		canAddCollection = false,
		maxCollectionSetDepth = 0,
	}
end

function exportServiceProvider.goToPublishedCollection(publishSettings, _)
	LrHttp.openUrlInBrowser("https://www.inaturalist.org/observations/" .. publishSettings.login)
end

local function checkSettings(settings)
	local suggestions = {}

	if not settings.LR_size_doNotEnlarge then
		table.insert(suggestions, LOC('$$$/iNat/Export/SuggestionDoNotEnlarge= - Select "Don\'t Enlarge"'))
	end

	local t = settings.LR_size_resizeType
	if not t then
		table.insert(
			suggestions,
			LOC("$$$/iNat/Export/SuggestionResize= - Resize to Fit, Long Edge, 2048 pixels or fewer")
		)
	elseif t == "wh" or t == "dimensions" then
		local longEdge = math.max(settings.LR_size_maxHeight, settings.LR_size_maxWidth)
		if longEdge > 2048 then
			table.insert(
				suggestions,
				LOC('$$$/iNat/Export/SuggestionUseLongEdge= - Consider using "Long Edge" instead')
			)
			table.insert(
				suggestions,
				LOC("$$$/iNat/Export/SuggestionReduceSize= - Reduce image size to 2048 pixels or fewer")
			)
		end
	elseif t == "longEdge" then
		if settings.LR_size_maxHeight > 2048 then
			table.insert(
				suggestions,
				LOC("$$$/iNat/Export/SuggestionReduceLongEdge= - Reduce long edge size to 2048 pixels or fewer")
			)
		end
	elseif t == "shortEdge" then
		table.insert(
			suggestions,
			LOC('$$$/iNat/Export/SuggestionLongEdgeInstead= - Use "Long Edge" instead of "Short Edge"')
		)
		if settings.LR_size_maxHeight > 2048 then
			table.insert(
				suggestions,
				LOC("$$$/iNat/Export/SuggestionReduceEdge= - Reduce edge size to 2048 pixels or fewer")
			)
		end
	elseif t == "megapixels" then
		table.insert(
			suggestions,
			LOC('$$$/iNat/Export/SuggestionLongEdgeNotMP= - Use "Long Edge" instead of "Megapixels"')
		)
		-- 2048px*2048px = 4.194304 MP
		if settings.LR_size_megapixels > 4.2 then
			table.insert(
				suggestions,
				LOC('$$$/iNat/Export/SuggestionLimitMP= - If you need to use "Megapixels", limit to less than 4.2')
			)
		end
	elseif t == "percentage" then
		table.insert(
			suggestions,
			LOC('$$$/iNat/Export/SuggestionLongEdgeNotPercent= - Use "Long Edge" instead of "Percentage"')
		)
	end

	if #suggestions == 0 then
		return
	end

	local intro = LOC(
		"$$$/iNat/Export/SizingWarningIntro=iNaturalist limits image uploads to 2048 pixels on the long "
			.. "side. The size settings you have chosen may result in larger images, so uploads could take "
			.. "a longer time than needed, and waste server resources on iNaturalist.\n\nSuggestions in "
			.. '"Image Sizing" section of settings:\n\n'
	)

	local trailer = LOC(
		"$$$/iNat/Export/SizingWarningTrailer=\n\nPlease open publish service settings again to edit the "
			.. "image sizing settings."
	)

	local suggStr = table.concat(suggestions, "\n")
	LrDialogs.resetDoNotShowFlag(suggStr)

	LrDialogs.messageWithDoNotShow({
		message = LOC("$$$/iNat/Export/SizingWarningTitle=Image sizing too large"),
		info = intro .. suggStr .. trailer,
		actionPrefKey = sha2.sha256(suggStr),
	})
end

function exportServiceProvider.didCreateNewPublishService(publishSettings, info)
	-- Emulates the setup we have when editing config
	publishSettings.LR_publishService = info.publishService

	local f = LrView.osFactory()
	local mainMsg = LOC("$$$/iNat/Export/SyncWillTakeTime=This will take some time.")
	if publishSettings.syncOnPublish then
		mainMsg = LOC(
			"$$$/iNat/Export/SyncWillTakeTimeAuto=This will take some time. If you do not do this now it "
				.. "will happen automatically the first time you publish using this plugin."
		)
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
			title = LOC(
				"$$$/iNat/Export/NoCollectionWarning=You have not set a collection to which to limit the "
					.. "search for matching photos. This may result in a low number of matches."
			),
			fill_horizontal = 1,
			width_in_chars = 50,
			height_in_lines = 2,
		})
	end
	local r = LrDialogs.presentModalDialog({
		title = LOC("$$$/iNat/Export/PerformSyncNowTitle=Perform synchronization from iNaturalist now?"),
		contents = f:column(c),
	})

	if r == "ok" then
		SyncObservations.fullSync(publishSettings)
	end
end

function exportServiceProvider.didUpdatePublishService(publishSettings, _)
	checkSettings(publishSettings)
end

-- function exportServiceProvider.canAddCommentsToService(publishSettings)
-- return INaturalistAPI.testConnection(publishSettings)
-- end
--

return exportServiceProvider
