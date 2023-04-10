local INaturalistMetadata = require("INaturalistMetadata")

return {
	metadataFieldsForPhotos = {
		{
			id = INaturalistMetadata.ObservationUUID,
			title = "Observation UUID",
			dataType = "string",
			readOnly = true,
			searchable = true,
			browsable = false,
			version = 1,
		},
		{
			id = INaturalistMetadata.ObservationURL,
			title = "Observation URL",
			dataType = "url",
			readOnly = true,
			searchable = false,
			version = 1,
		},
		{
			id = INaturalistMetadata.CommonName,
			title = "Common name",
			dataType = "string",
			readOnly = true,
			searchable = true,
			browsable = false,
		},
		{
			id = INaturalistMetadata.Name,
			title = "Name",
			dataType = "string",
			readOnly = true,
			searchable = true,
			browsable = false,
		},
		{
			id = INaturalistMetadata.CommonTaxonomy,
			title = "Common name taxonomy",
			dataType = "string",
			readOnly = true,
			searchable = true,
			browsable = false,
		},
		{
			id = INaturalistMetadata.Taxonomy,
			title = "Taxonomy",
			dataType = "string",
			readOnly = true,
			searchable = true,
			browsable = false,
		},
	},

	schemaVersion = 1,
}
