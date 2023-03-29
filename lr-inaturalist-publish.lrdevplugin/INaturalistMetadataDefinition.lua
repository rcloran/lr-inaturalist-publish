require("INaturalistMetadata")

return {
	metadataFieldsForPhotos = {
		{
			id = INaturalistMetadata.ObservationUUID,
			title = "Observation UUID",
			dataType = "string",
			readOnly = true,
			searchable = false,
		},
		{
			id = INaturalistMetadata.ObservationURL,
			title = "Observation URL",
			dataType = "url",
			readOnly = true,
			searchable = false,
			version = 1,
		},
	},

	schemaVersion = 1,
}
