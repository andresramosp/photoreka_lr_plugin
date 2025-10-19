-- CÓDIGO REHECHO DESDE CERO - Enfoque minimalista con Grid y Exportación
local LrTasks = import 'LrTasks'
local LrApplication = import 'LrApplication'
local LrDialogs = import 'LrDialogs'
local LrView = import 'LrView'
local LrBinding = import 'LrBinding'
local LrFunctionContext = import 'LrFunctionContext'
local LrHttp = import 'LrHttp'
local LrPathUtils = import 'LrPathUtils'
local LrLogger = import 'LrLogger'

-- Configurar logger
local log = LrLogger('PhotorekaPlugin')
log:enable("logfile")

-- Servicios personalizados
local Config = require 'Config'
local ExportService = require 'ExportService'
local ApiService = require 'ApiService'
local ExifService = require 'ExifService'
local AuthService = require 'AuthService'

log:info("========================================")
log:info("MAIN.LUA EJECUTÁNDOSE")
log:info("========================================")

-- Función auxiliar para obtener nombre de archivo
local function getFileName(filePath)
    if filePath then
        return LrPathUtils.leafName(filePath)
    end
    return nil
end

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
    
    -- Crear propiedades observables para el checkbox
    local props = LrBinding.makePropertyTable(context)
    props.onlyToLightbox = false
    props.photoCount = #photos
    
    -- Construir el grid con miniaturas
    local thumbnailRows = {}
    local photosPerRow = 4
    local currentRow = {}
    
    for i, photo in ipairs(photos) do
        -- Cada miniatura
        local thumbnailItem = f:column {
            spacing = f:label_spacing(),
            
            f:catalog_photo {
                photo = photo,
                width = 150,
                height = 150,
            },
        }
        
        table.insert(currentRow, thumbnailItem)
        
        -- Si completamos una fila o es la última foto
        if #currentRow == photosPerRow or i == #photos then
            table.insert(thumbnailRows, f:row(currentRow))
            currentRow = {}
        end
    end
    
    -- Obtener información del usuario autenticado (si existe)
    local userInfo = AuthService.getStoredUserInfo()
    local accountButtonTitle = userInfo and string.format('👤 %s', userInfo.name or userInfo.email) or '👤 Cuenta'
    
    -- Crear el contenido del diálogo
    local dialogContent = f:column {
        bind_to_object = props,
        spacing = f:control_spacing(),
        

        
        -- Header con título y botón de cuenta
        f:row {
            fill_horizontal = 1,
            
            f:static_text {
                title = LrView.bind {
                    key = 'photoCount',
                    transform = function(value)
                        return string.format('Selected photos: %d', value)
                    end
                },
                font = '<system/bold>',
            },
            
            f:spacer { fill_horizontal = 1 },
            
            f:push_button {
                title = accountButtonTitle,
                action = function()
                    AuthService.showAccountDialog()
                end,
            },
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
        
        -- Checkbox para modo "Only to Lightbox"
        f:checkbox {
            title = 'Only to Lightbox (check for filtering or reviewing duplicates)',
            value = LrView.bind('onlyToLightbox'),
        },

    }
    
    -- Mostrar el diálogo con botón "Procesar"
    local result = LrDialogs.presentModalDialog({
        title = 'Export to Photoreka',
        contents = dialogContent,
        actionVerb = 'Export',
        cancelVerb = 'Cancel',
    })
    
    -- Si el usuario hace clic en "Procesar"
    if result == 'ok' then
        -- Capturar el valor del checkbox antes de salir del contexto
        local onlyToLightbox = props.onlyToLightbox
        
        -- Ejecutar exportación y envío en async task
        LrTasks.startAsyncTask(function()
            -- PRIMERO: Verificar autenticación antes de iniciar la exportación
            log:info("Usuario pulsó Procesar, verificando autenticación...")
            local token = AuthService.ensureAuthenticated()
            
            if not token or token == '' then
                log:info("Autenticación cancelada o falló, abortando proceso")
                LrDialogs.message(
                    'Export to Photoreka',
                    'Process cancelled. You must log in to continue.',
                    'info'
                )
                return
            end
            
            log:info("Autenticación exitosa, iniciando exportación...")
            
            -- Crear carpeta temporal
            local exportFolder = ExportService.createTempFolder()
            
            -- Variable para almacenar resultados
            local uploadResult = nil
            
            LrFunctionContext.callWithContext('exportPhotos', function(exportContext)
                -- Mostrar barra de progreso
                local progressScope = LrDialogs.showModalProgressDialog({
                    title = 'Submitting photos to Photoreka server...',
                    functionContext = exportContext,
                })
                
                -- FASE 1: Exportación (40% del progreso total)
                progressScope:setCaption('Step 1/3: Exporting photos...')
                
                local exportedData = ExportService.exportPhotos(
                    photos,
                    exportFolder,
                    function(current, total, caption)
                        -- 0-40% del progreso total
                        local progress = (current / total) * 0.4
                        progressScope:setPortionComplete(progress, 1)
                        progressScope:setCaption('Step 1/3: ' .. caption)
                    end
                )
                
                -- FASE 2: Extracción de EXIF (10% del progreso total)
                progressScope:setCaption('Step 2/3: Extracting EXIF data...')
                
                local exifDataList = {}
                local sourceDataList = {}
                for i, photo in ipairs(photos) do
                    local progress = 0.4 + (i / #photos) * 0.1
                    progressScope:setPortionComplete(progress, 1)
                    
                    -- Extraer uniqueId de Lightroom
                    local uniqueId
                    catalog:withReadAccessDo(function()
                        uniqueId = photo.localIdentifier or photo:getRawMetadata('uuid')
                    end)
                    
                    local sourceData = {
                        type = "lightroom",
                        uniqueId = uniqueId
                    }
                    table.insert(sourceDataList, sourceData)
                    
                    -- Extraer EXIF reales de la foto
                    local exifData
                    catalog:withReadAccessDo(function()
                        exifData = ExifService.extractExifData(photo)
                    end)
                    table.insert(exifDataList, exifData)
                end
                
                -- FASE 3: Envío a la API (50% restante)
                progressScope:setCaption('Step 3/3: Submitting photos to Photoreka server...')
                
                exportedData.exifDataList = exifDataList
                exportedData.sourceDataList = sourceDataList
                
                uploadResult = ApiService.uploadPhotos(
                    exportedData,
                    function(current, total, caption)
                        -- 50-100% del progreso total
                        local progress = 0.5 + (current / total) * 0.5
                        progressScope:setPortionComplete(progress, 1)
                        progressScope:setCaption('Step 3/3: ' .. caption)
                    end,
                    onlyToLightbox  -- Pasar el parámetro onlyToLightbox
                )
                
                -- Cerrar el diálogo de progreso
                progressScope:done()
                
            end) -- Fin del contexto de progreso
            
            -- Verificar que se haya completado el proceso
            if not uploadResult then
                log:error("Error: No se obtuvieron resultados del upload")
                return
            end
            
            -- Esperar un momento para asegurar que el diálogo de progreso se cierre
            LrTasks.sleep(0.3)
            
            -- Preparar mensaje de resultado
            local successCount = #uploadResult.successfulUploads
            local failureCount = #uploadResult.failedUploads
            local totalCount = successCount + failureCount
            
            local statusText
            local statusFont
            if failureCount == 0 then
                statusText = '✓ Process completed successfully'
                statusFont = '<system/bold>'
            elseif successCount == 0 then
                statusText = '✗ Error: No photos could be uploaded'
                statusFont = '<system/bold>'
            else
                statusText = '⚠ Process completed with errors'
                statusFont = '<system/bold>'
            end
            
            -- Construir diálogo de resultado
            local dialogComponents = {
                spacing = f:control_spacing(),
                
                -- Logo
                f:row {
                    fill_horizontal = 1,
                    
                    f:spacer { fill_horizontal = 1 },
                    
                    f:picture {
                        value = _PLUGIN.path .. '/logo_full.png',
                        height = 80,
                    },
                    
                    f:spacer { fill_horizontal = 1 },
                },
                
                f:spacer { height = 8 },
                
                f:static_text {
                    title = statusText,
                    font = statusFont,
                },
                
                f:separator { fill_horizontal = 1 },
                
                f:static_text {
                    title = string.format(
                        'Successful: %d of %d | Failed: %d',
                        successCount,
                        totalCount,
                        failureCount
                    ),
                },
                
                f:spacer { height = 10 },
            }
            
            -- Mostrar errores si los hay
            if failureCount > 0 then
                table.insert(dialogComponents, f:static_text {
                    title = 'Errors found:',
                    font = '<system/small>',
                })
                
                for i = 1, math.min(3, failureCount) do
                    local failure = uploadResult.failedUploads[i]
                    table.insert(dialogComponents, f:static_text {
                        title = string.format('• %s', getFileName(failure.mainPath) or 'Unknown'),
                        font = '<system/small>',
                        text_color = LrView.kLabelColor,
                    })
                end
                
                if failureCount > 3 then
                    table.insert(dialogComponents, f:static_text {
                        title = string.format('... and %d more', failureCount - 3),
                        font = '<system/small>',
                    })
                end
                
                table.insert(dialogComponents, f:spacer { height = 10 })
            end
            
            
            
            -- table.insert(dialogComponents, f:spacer { height = 15 })
            
            -- Enlace a Photoreka (varía según el modo)
            if successCount > 0 then
                local linkText, linkUrl
                if onlyToLightbox then
                    linkText = '🔎 Review your photos here before processing'
                    linkUrl = 'https://www.photoreka.com/photo-hub#upload'
                else
                    linkText = '🔎 Monitor processing here'
                    linkUrl = 'https://www.photoreka.com/photo-hub#processing'
                end
                
                table.insert(dialogComponents, f:static_text {
                    title = linkText,
                })
                
                table.insert(dialogComponents, f:row {
                    f:push_button {
                        title = linkUrl,
                        action = function()
                            LrHttp.openUrlInBrowser(linkUrl)
                        end,
                    },
                })
            end
            
            local dialogResult = f:column(dialogComponents)
            
            LrDialogs.presentModalDialog({
                title = 'Export to Photoreka',
                contents = dialogResult,
                actionVerb = 'Close',
            })
            
            -- Limpiar carpeta temporal después de mostrar el diálogo
            log:info("Eliminando carpeta temporal: " .. exportFolder)
            ExportService.deleteTempFolder(exportFolder)
            log:info("Carpeta temporal eliminada correctamente")
        end)
    end
    
end)
