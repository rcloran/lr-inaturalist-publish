local MetadataConst = require("MetadataConst")

return {
	metadataFieldsForPhotos = {
		{
			id = MetadataConst.ObservationUUID,
			title = "Observation UUID",
			dataType = "string",
			readOnly = true,
			searchable = true,
			browsable = false,
			version = 1,
		},
		{
			id = MetadataConst.ObservationURL,
			title = "Observation URL",
			dataType = "url",
			readOnly = true,
			searchable = false,
			version = 1,
		},
		{
			id = MetadataConst.CommonName,
			title = "Common name",
			dataType = "string",
			readOnly = true,
			searchable = true,
			browsable = false,
		},
		{
			id = MetadataConst.Name,
			title = "Name",
			dataType = "string",
			readOnly = true,
			searchable = true,
			browsable = false,
		},
		{
			id = MetadataConst.CommonTaxonomy,
			title = "Common name taxonomy",
			dataType = "string",
			readOnly = true,
			searchable = true,
			browsable = false,
		},
		{
			id = MetadataConst.Taxonomy,
			title = "Taxonomy",
			dataType = "string",
			readOnly = true,
			searchable = true,
			browsable = false,
		},
	},

	schemaVersion = 1,
}
