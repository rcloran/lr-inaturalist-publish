local MetadataConst = require("MetadataConst")

return {
	metadataFieldsForPhotos = {
		{
			id = MetadataConst.ObservationUUID,
			title = LOC("$$$/iNat/Metadata/ObservationUUID=Observation UUID"),
			dataType = "string",
			readOnly = true,
			searchable = true,
			browsable = false,
			version = 1,
		},
		{
			id = MetadataConst.ObservationURL,
			title = LOC("$$$/iNat/Metadata/ObservationURL=Observation URL"),
			dataType = "url",
			readOnly = true,
			searchable = false,
			version = 1,
		},
		{
			id = MetadataConst.CommonName,
			title = LOC("$$$/iNat/Metadata/CommonName=Common name"),
			dataType = "string",
			readOnly = true,
			searchable = true,
			browsable = false,
		},
		{
			id = MetadataConst.Name,
			title = LOC("$$$/iNat/Metadata/Name=Name"),
			dataType = "string",
			readOnly = true,
			searchable = true,
			browsable = false,
		},
		{
			id = MetadataConst.CommonTaxonomy,
			title = LOC("$$$/iNat/Metadata/CommonTaxonomy=Common name taxonomy"),
			dataType = "string",
			readOnly = true,
			searchable = true,
			browsable = false,
		},
		{
			id = MetadataConst.Taxonomy,
			title = LOC("$$$/iNat/Metadata/Taxonomy=Taxonomy"),
			dataType = "string",
			readOnly = true,
			searchable = true,
			browsable = false,
		},
	},

	schemaVersion = 1,
}
