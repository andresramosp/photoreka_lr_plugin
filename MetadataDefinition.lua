-- MetadataDefinition.lua - Define el metadato personalizado de Photoreka
return {
    metadataFieldsForPhotos = {
        {
            id = 'photorekaanalyzed',
            title = 'Analyzed by Photoreka',
            dataType = 'enum',
            values = {
                {
                    value = true,
                    title = 'Yes',
                },
                {
                    value = false,
                    title = 'No',
                },
            },
            searchable = true,
            browsable = true,
        },
        {
            id = 'photorekasearchmetadata',
            title = 'Photoreka Search Metadata Applied',
            dataType = 'enum',
            values = {
                {
                    value = true,
                    title = 'Yes',
                },
                {
                    value = false,
                    title = 'No',
                },
            },
            searchable = true,
            browsable = true,
        },
    },
    
    schemaVersion = 2,
}
