local menuItems = {
	{
		title = LOC("$$$/iNat/Menu/GroupPhotos=Group photos into observation"),
		file = "GroupObservation.lua",
		enabledWhen = "photosSelected",
	},
	{
		title = LOC("$$$/iNat/Menu/ClearObservation=Clear observation"),
		file = "ClearObservation.lua",
		enabledWhen = "photosSelected",
	},
}

-- This is substituted by the build script, based on git tags.
local DEV_VERSION = { major = 0, minor = 1, revision = 0, display = "Development" }

return {
	-- Have not tried to check what the right value is here. Guess.
	LrSdkVersion = 6,

	LrToolkitIdentifier = "net.rcloran.lr-inaturalist-publish",
	LrPluginName = LOC("$$$/iNat/PluginName=iNaturalist"),

	LrInitPlugin = "InitPlugin.lua",

	LrPluginInfoProvider = "PluginInfoProvider.lua",

	LrExportServiceProvider = {
		title = LOC("$$$/iNat/ExportService/Title=iNaturalist"),
		file = "ExportServiceProvider.lua",
	},

	URLHandler = "URLHandler.lua",

	LrMetadataProvider = "MetadataDefinition.lua",

	LrExportMenuItems = menuItems,
	LrLibraryMenuItems = menuItems,

	VERSION = DEV_VERSION,
}
