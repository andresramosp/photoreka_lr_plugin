-- CÓDIGO REHECHO DESDE CERO - Enfoque minimalista con Grid y Exportación
local LrTasks = import 'LrTasks'
local LrApplication = import 'LrApplication'
local LrDialogs = import 'LrDialogs'
local LrView = import 'LrView'
local LrBinding = import 'LrBinding'
local LrFunctionContext = import 'LrFunctionContext'
local LrHttp = import 'LrHttp'

-- Servicios personalizados
local ExportService = require 'ExportService'
local ApiService = require 'ApiService'

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
            title = 'Las fotos se exportarán en dos versiones: Full (1500px) y Thumbnail (800px).',
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
        -- Crear carpeta temporal
        local exportFolder = ExportService.createTempFolder()
        
        -- Ejecutar exportación y envío en async task
        LrTasks.startAsyncTask(function()
            LrFunctionContext.callWithContext('exportPhotos', function(exportContext)
                -- Mostrar barra de progreso
                local progressScope = LrDialogs.showModalProgressDialog({
                    title = 'Procesando y enviando fotos...',
                    functionContext = exportContext,
                })
                
                -- FASE 1: Exportación (50% del progreso total)
                progressScope:setCaption('Fase 1/2: Exportando fotos (full + thumbs)...')
                
                local exportedData = ExportService.exportPhotos(
                    photos,
                    exportFolder,
                    function(current, total, caption)
                        -- 0-50% del progreso total
                        local progress = (current / total) * 0.5
                        progressScope:setPortionComplete(progress, 1)
                        progressScope:setCaption('Fase 1/2: ' .. caption)
                    end
                )
                
                -- FASE 2: Envío por lotes a la API (50% restante)
                progressScope:setCaption('Fase 2/2: Enviando fotos a Photoreka...')
                
                ApiService.uploadPhotos(
                    exportedData,
                    function(current, total, caption)
                        -- 50-100% del progreso total
                        local progress = 0.5 + (current / total) * 0.5
                        progressScope:setPortionComplete(progress, 1)
                        progressScope:setCaption('Fase 2/2: ' .. caption)
                    end
                )
                
                progressScope:done()
                
                -- Mostrar resultado final con enlace
                local dialogResult = f:column {
                    spacing = f:control_spacing(),
                    
                    f:static_text {
                        title = '✓ Proceso completado con éxito',
                        font = '<system/bold>',
                    },
                    
                    f:separator { fill_horizontal = 1 },
                    
                    f:static_text {
                        title = string.format('%d fotos exportadas (full + thumbs) y enviadas correctamente.', #exportedData.fullPhotos),
                    },
                    
                    f:spacer { height = 10 },
                    
                    f:static_text {
                        title = 'Carpeta temporal:',
                        font = '<system/small>',
                    },
                    
                    f:static_text {
                        title = exportFolder,
                        font = '<system/small>',
                        text_color = LrView.kLabelColor,
                    },
                    
                    f:spacer { height = 15 },
                    
                    f:static_text {
                        title = 'Visita tu galería en:',
                    },
                    
                    f:row {
                        f:push_button {
                            title = '🌐 www.photoreka.com',
                            action = function()
                                LrHttp.openUrlInBrowser('https://www.photoreka.com')
                            end,
                        },
                    },
                }
                
                LrDialogs.presentModalDialog({
                    title = 'Export to Photoreka',
                    contents = dialogResult,
                    actionVerb = 'Cerrar',
                })
            end)
        end)
    end
    
end)
