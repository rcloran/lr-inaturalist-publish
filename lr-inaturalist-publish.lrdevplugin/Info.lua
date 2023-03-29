local menuItems = {
	{
		title = "Group photos into observation",
		file = "GroupObservation.lua",
		enabledWhen = "photosSelected",
	},
	{
		title = "Clear observation",
		file = "ClearObservation.lua",
		enabledWhen = "photosSelected",
	},
}

return {
	-- Have not tried to check what the right value is here. Guess.
	LrSdkVersion = 6,

	LrToolkitIdentifier = "net.rcloran.lr-inaturalist-publish",
	LrPluginName = "iNaturalist",

	LrInitPlugin = "InitPlugin.lua",

	LrExportServiceProvider = {
		title = "iNaturalist",
		file = "INaturalistExportServiceProvider.lua",
	},

	URLHandler = "URLHandler.lua",

	LrMetadataProvider = "INaturalistMetadataDefinition.lua",

	LrExportMenuItems = menuItems,
	LrLibraryMenuItems = menuItems,

	VERSION = { major = 0, minor = 1, revision = 0 },
}
