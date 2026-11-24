return {
    LrSdkVersion = 6.0,
    LrSdkMinimumVersion = 6.0,
    LrToolkitIdentifier = 'com.tuusuario.holamundo',
    LrPluginName = "Photoreka",
    LrInitPlugin = "Init.lua",
    
    -- VERSION = { major=1, minor=0, revision=0, build=0 },
    
    -- Metadato personalizado para marcar fotos analizadas por Photoreka
    LrMetadataProvider = 'MetadataDefinition.lua',
    
    -- Agrega un ítem de menú en Biblioteca > Extras del módulo
    LrLibraryMenuItems = {
        {
            title = "👤 Account",
            file = "ManageAccount.lua",
        },
        {
            title = "🗂️ Your Workspace",
            file = "ShowPhotorekaCatalog.lua",
        },
        {
            title = "🚀 Analyze Photos",
            file = "Main.lua",
            -- enabledWhen = "photosSelected"
        },
        {
            title = "🔎 Search Photos",
            file = "Search.lua",
        },
        {
            title = "🛠️ Export to Tool",
            file = "ExportToPhotoreka.lua",
            -- enabledWhen = "photosSelected"
        },
        {
            title = "🌐 Web App",
            file = "OpenWebApp.lua",
        },
    },

    -- Agrega el mismo ítem en Archivo > Extras del módulo (accesible desde cualquier módulo)
    LrExportMenuItems = {
        {
            title = "👤 Account",
            file = "ManageAccount.lua",
        },
        {
            title = "🗂️ Your Workspace",
            file = "ShowPhotorekaCatalog.lua",
        },
        {
            title = "🚀 Analyze Photos",
            file = "Main.lua",
            -- enabledWhen = "photosSelected"
        },
        {
            title = "🔎 Search Photos",
            file = "Search.lua",
        },
        {
            title = "🛠️ Export to Tool",
            file = "ExportToPhotoreka.lua",
            -- enabledWhen = "photosSelected"
        },
        {
            title = "🌐 Web App",
            file = "OpenWebApp.lua",
        },
      
    },
}
