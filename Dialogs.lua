-- CÓDIGO REHECHO DESDE CERO - Enfoque minimalista con Grid y Exportación
local LrTasks = import 'LrTasks'
local LrApplication = import 'LrApplication'
local LrDialogs = import 'LrDialogs'
local LrView = import 'LrView'
local LrBinding = import 'LrBinding'
local LrExportSession = import 'LrExportSession'
local LrPathUtils = import 'LrPathUtils'
local LrFileUtils = import 'LrFileUtils'
local LrFunctionContext = import 'LrFunctionContext'

-- Ejecutar en un async task para permitir diálogos
LrFunctionContext.callWithContext('showDialog', function(context)
    
    local catalog = LrApplication.activeCatalog()
    local photos = {}
    
    -- Leer del catálogo TODO de una vez
    catalog:withReadAccessDo(function()
        -- Intentar obtener fotos seleccionadas
        photos = catalog:getTargetPhotos()
        
        -- Si no hay selección, intentar con fuentes activas
        if not photos or #photos == 0 then
            local sources = catalog:getActiveSources()
            if sources and #sources > 0 then
                for _, source in ipairs(sources) do
                    if source.getPhotos then
                        local sourcePhotos = source:getPhotos()
                        if sourcePhotos then
                            for _, p in ipairs(sourcePhotos) do
                                table.insert(photos, p)
                            end
                        end
                    end
                end
            end
        end
    end)
    
    -- Ya estamos FUERA del withReadAccessDo - ahora podemos mostrar diálogos
    
    if #photos == 0 then
        LrDialogs.message('Export to Photoreka', 'No hay fotos seleccionadas.', 'info')
        return
    end
    
    -- Crear el grid de miniaturas
    local f = LrView.osFactory()
    
    -- Construir el grid con miniaturas
    local thumbnailRows = {}
    local photosPerRow = 4
    local currentRow = {}
    
    for i, photo in ipairs(photos) do
        table.insert(currentRow, f:catalog_photo {
            photo = photo,
            width = 150,
            height = 150,
        })
        
        -- Si completamos una fila o es la última foto
        if #currentRow == photosPerRow or i == #photos then
            table.insert(thumbnailRows, f:row(currentRow))
            currentRow = {}
        end
    end
    
    -- Crear el contenido del diálogo
    local dialogContent = f:column {
        spacing = f:control_spacing(),
        
        f:static_text {
            title = string.format('Fotos seleccionadas: %d', #photos),
            font = '<system/bold>',
        },
        
        f:separator { fill_horizontal = 1 },
        
        -- Scrolled view para el grid
        f:scrolled_view {
            horizontal_scroller = false,
            width = 650,
            height = 400,
            f:column(thumbnailRows),
        },
        
        f:separator { fill_horizontal = 1 },
        
        f:static_text {
            title = 'Las fotos se exportarán como JPEG con máximo 1500px de lado.',
            font = '<system/small>',
        },
    }
    
    -- Mostrar el diálogo con botón "Procesar"
    local result = LrDialogs.presentModalDialog({
        title = 'Export to Photoreka',
        contents = dialogContent,
        actionVerb = 'Procesar',
        cancelVerb = 'Cancelar',
    })
    
    -- Si el usuario hace clic en "Procesar"
    if result == 'ok' then
        -- Crear carpeta temporal para las imágenes procesadas
        local tempFolder = LrPathUtils.getStandardFilePath('temp')
        local exportFolder = LrPathUtils.child(tempFolder, 'PhotorekaExport_' .. os.time())
        LrFileUtils.createDirectory(exportFolder)
        
        -- Configurar la sesión de exportación
        local exportSettings = {
            LR_export_destinationType = 'specificFolder',
            LR_export_destinationPathPrefix = exportFolder,
            LR_format = 'JPEG',
            LR_jpeg_quality = 0.9,
            LR_size_doConstrain = true,
            LR_size_maxWidth = 1500,
            LR_size_maxHeight = 1500,
            LR_size_resolution = 72,
            LR_size_resolutionUnits = 'inch',
            LR_reimportExportedPhoto = false,
            LR_export_colorSpace = 'sRGB',
        }
        
        -- Ejecutar exportación en async task
        LrTasks.startAsyncTask(function()
            LrFunctionContext.callWithContext('exportPhotos', function(exportContext)
                -- Mostrar barra de progreso
                local progressScope = LrDialogs.showModalProgressDialog({
                    title = 'Procesando fotos...',
                    functionContext = exportContext,
                })
                
                -- Realizar la exportación
                local exportSession = LrExportSession({
                    photosToExport = photos,
                    exportSettings = exportSettings,
                })
                
                local exportedFiles = {}
                local totalPhotos = #photos
                local currentPhoto = 0
                
                for _, rendition in exportSession:renditions() do
                    currentPhoto = currentPhoto + 1
                    progressScope:setPortionComplete(currentPhoto, totalPhotos)
                    progressScope:setCaption(string.format('Procesando foto %d de %d...', currentPhoto, totalPhotos))
                    
                    local success, pathOrMessage = rendition:waitForRender()
                    
                    if success then
                        table.insert(exportedFiles, pathOrMessage)
                    end
                end
                
                progressScope:done()
                
                -- Mostrar resultado
                LrDialogs.message(
                    'Exportación completada',
                    string.format(
                        '%d fotos procesadas correctamente.\n\nGuardadas en:\n%s\n\nListas para enviar a la API.',
                        #exportedFiles,
                        exportFolder
                    ),
                    'info'
                )
            end)
        end)
    end
    
end)
