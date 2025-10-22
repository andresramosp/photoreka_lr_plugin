return {
    LrSdkVersion = 6.0,
    LrSdkMinimumVersion = 6.0,
    LrToolkitIdentifier = 'com.tuusuario.holamundo',
    LrPluginName = "Photoreka",
    LrInitPlugin = "Init.lua",
    
    -- VERSION = { major=1, minor=0, revision=0, build=0 },
    
    -- Agrega un ítem de menú en Biblioteca > Extras del módulo
    LrLibraryMenuItems = {
        {
            title = "Analyze Photos",
            file = "Main.lua",
        },
        {
            title = "Search",
            file = "Search.lua",
        },
    },

    -- Agrega el mismo ítem en Archivo > Extras del módulo (accesible desde cualquier módulo)
    LrExportMenuItems = {
        {
            title = "Analyze Photos",
            file = "Main.lua",
        },
        {
            title = "Search",
            file = "Search.lua",
        },
        {
            title = "Canvas",
            file = "OpenCanvas.lua",
        },
        {
            title = "3D Atlas",
            file = "Open3DAtlas.lua",
        },
    },
}
