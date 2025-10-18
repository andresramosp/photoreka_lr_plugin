return {
    LrSdkVersion = 6.0,
    LrSdkMinimumVersion = 6.0,
    LrToolkitIdentifier = 'com.tuusuario.holamundo',
    LrPluginName = "Photoreka",
    LrInitPlugin = "Init.lua",
    
    -- Agrega un ítem de menú en Biblioteca > Extras del módulo
    LrLibraryMenuItems = {
        {
            title = "Export to Photoreka",
            file = "Dialogs.lua", -- Lightroom ejecuta este archivo al hacer clic
        },
    },

    -- Agrega el mismo ítem en Archivo > Extras del módulo (accesible desde cualquier módulo)
    LrExportMenuItems = {
        {
            title = "Export to Photoreka",
            file = "Dialogs.lua", -- también accesible desde Archivo > Extras del módulo
        },
    },
}
