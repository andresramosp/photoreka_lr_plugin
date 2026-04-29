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
local PhotorekaCatalogService = require 'PhotorekaCatalogService'

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

-- Envolver todo en una tarea async para evitar errores de "wait from within a task"
LrTasks.startAsyncTask(function()
LrFunctionContext.callWithContext('showDialog', function(context)
    
    local catalog = LrApplication.activeCatalog()
    local photos = {}
    local hasSelection = false
    local shouldCheckSources = false
    local activeSources = {}
    local singlePhoto = nil
    local isAutoSelectionFirst = false -- Heuristic: auto-selected first photo of active source
    
    -- Leer del catálogo TODO de una vez
    catalog:withReadAccessDo(function()
        -- Verificar si hay una selección explícita usando getTargetPhoto (singular)
        -- Si devuelve nil, no hay selección
    singlePhoto = catalog:getTargetPhoto()
    hasSelection = (singlePhoto ~= nil)
        
        -- Obtener todas las fotos target
        photos = catalog:getTargetPhotos()
        
        -- Si solo hay 1 foto seleccionada, marcar para verificar fuentes activas
        if #photos == 1 then
            shouldCheckSources = true
            activeSources = catalog:getActiveSources()
        end
    end)
    
    -- FUERA de withReadAccessDo: decidir si expandimos a colecciones activas
    -- Regla: SOLO si la única foto seleccionada es la primera de alguna fuente activa
    if shouldCheckSources and activeSources and #activeSources > 0 and singlePhoto then
        -- Primero detectar si coincide con el primer elemento de alguna fuente
        for _, source in ipairs(activeSources) do
            if source.getPhotos then
                local photosFromSource = source:getPhotos()
                if photosFromSource and #photosFromSource > 0 then
                    local firstPhoto = photosFromSource[1]
                    if firstPhoto and firstPhoto.localIdentifier == singlePhoto.localIdentifier then
                        isAutoSelectionFirst = true
                        break
                    end
                end
            end
        end

        -- Si es la primera, ahora sí cargamos TODAS las fotos de las fuentes activas
        if isAutoSelectionFirst then
            local sourcePhotos = {}
            for _, source in ipairs(activeSources) do
                if source.getPhotos then
                    local photosFromSource = source:getPhotos()
                    if photosFromSource then
                        for _, p in ipairs(photosFromSource) do
                            table.insert(sourcePhotos, p)
                        end
                    end
                end
            end

            -- Nota: aquí podría haber ambigüedad en el futuro. Ver TODO abajo.
            log:info(string.format(
                "Detected single selection equals first photo of an active source. Expanding to full sources (%d photos).",
                #sourcePhotos
            ))
            photos = sourcePhotos
        else
            -- El usuario seleccionó explícitamente una foto (no la primera). Respetar esa única selección.
            log:info("Single selected photo is not the first in active source(s). Treating as explicit single selection.")
        end
    end

    -- TODO: Ambigüedad y mejoras futuras
    -- 1) Preguntar al usuario cuando haya 1 seleccionada y active sources: "Process selected (1) or all from source (X)?"
    -- 2) Detectar y excluir la fuente "All Photographs" para evitar expandir el catálogo completo por accidente.
    -- 3) Agregar una preferencia en Config para controlar este comportamiento.
    
    -- Ya estamos FUERA del withReadAccessDo - ahora podemos mostrar diálogos
    
    -- Validar que haya fotos seleccionadas explícitamente
    if not hasSelection or not photos or #photos == 0 then
        LrDialogs.message(
            'Analyze Photos', 
            'Please select photos before exporting.', 
            'info'
        )
        return
    end
    
    -- Validar que no se exceda el máximo de fotos
    if #photos > Config.MAX_PHOTOS then
        LrDialogs.message(
            'Analyze Photos', 
            string.format('You can only process up to %d photos at a time. You have selected %d photos.', Config.MAX_PHOTOS, #photos), 
            'warning'
        )
        return
    end
    
    -- Crear el grid de miniaturas
    local f = LrView.osFactory()

    -- Extraer segmentos del path de la primera foto para el selector de root
    local firstPhotoSegments = {}
    catalog:withReadAccessDo(function()
        local path = photos[1]:getRawMetadata('path')
        if path and path ~= '' then
            local dir = LrPathUtils.parent(path)
            if dir then
                for seg in dir:gmatch('[^\\/]+') do
                    table.insert(firstPhotoSegments, seg)
                end
            end
        end
    end)

    -- Crear propiedades observables para el checkbox
    local props = LrBinding.makePropertyTable(context)
    props.onlyToLightbox = false
    props.mirrorFolderStructure = false
    props.mirrorRootIndex = 1
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

        -- Checkbox para replicar la estructura de carpetas de Lightroom
        -- como collections en Photoreka.
        f:checkbox {
            title = 'Mirror folder structure (replicate Lightroom folders as Photoreka collections)',
            value = LrView.bind('mirrorFolderStructure'),
        },

        f:row {
            enabled = LrView.bind('mirrorFolderStructure'),
            spacing = f:label_spacing(),
            f:static_text {
                title = 'Folders root:',
                enabled = LrView.bind('mirrorFolderStructure'),
            },
            f:popup_menu {
                items = (function()
                    local items = {}
                    for i, seg in ipairs(firstPhotoSegments) do
                        table.insert(items, { title = seg, value = i })
                    end
                    return items
                end)(),
                value = LrView.bind('mirrorRootIndex'),
                enabled = LrView.bind('mirrorFolderStructure'),
            },
        },

    }
    
    -- Mostrar el diálogo con botón "Procesar"
    local result = LrDialogs.presentModalDialog({
        title = 'Analyze Photos',
        contents = dialogContent,
        actionVerb = 'Export',
        cancelVerb = 'Cancel',
    })
    
    -- Si el usuario hace clic en "Procesar"
    if result == 'ok' then
        -- Capturar el valor del checkbox antes de salir del contexto
        local onlyToLightbox = props.onlyToLightbox
        local mirrorFolderStructure = props.mirrorFolderStructure
        local mirrorRootSegment = firstPhotoSegments[props.mirrorRootIndex] or firstPhotoSegments[1]
        
        -- Ejecutar exportación y envío en async task
        LrTasks.startAsyncTask(function()
            log:info('mirrorFolderStructure captured value = ' .. tostring(mirrorFolderStructure))
            -- PRIMERO: Verificar autenticación antes de iniciar la exportación
            log:info("Usuario pulsó Procesar, verificando autenticación...")
            local token = AuthService.ensureAuthenticated()
            
            if not token or token == '' then
                log:info("Autenticación cancelada o falló, abortando proceso")
                LrDialogs.message(
                    'Analyze Photos',
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

                    if mirrorFolderStructure then
                        catalog:withReadAccessDo(function()
                            local photoPath = photo:getRawMetadata('path')
                            if photoPath and photoPath ~= '' then
                                local dir = LrPathUtils.parent(photoPath)
                                if dir then
                                    local segments = {}
                                    for seg in dir:gmatch('[^\\/]+') do
                                        table.insert(segments, seg)
                                    end
                                    -- Find the root segment and exclude it: collections start AFTER it
                                    -- Case-insensitive match to handle Windows/macOS path casing
                                    local startIdx = #segments + 1
                                    if mirrorRootSegment then
                                        local rootLower = mirrorRootSegment:lower()
                                        for idx, seg in ipairs(segments) do
                                            if seg:lower() == rootLower then
                                                startIdx = idx + 1
                                                break
                                            end
                                        end
                                    end
                                    local trimmed = {}
                                    for idx = startIdx, #segments do
                                        table.insert(trimmed, segments[idx])
                                    end
                                    if #trimmed > 0 then
                                        sourceData.folderPath = trimmed
                                        sourceData.folderFullPath = segments  -- full path for collection description
                                    end
                                end
                            end
                        end)
                    end

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
            
            -- Marcar fotos exitosas con el metadato de Photoreka
            if uploadResult.successfulUploads and #uploadResult.successfulUploads > 0 then
                log:info("Marcando " .. tostring(#uploadResult.successfulUploads) .. " fotos como analizadas...")
                local markedPhotos = {}
                catalog:withWriteAccessDo('Mark Photoreka Analyzed', function()
                    for i, photoData in ipairs(uploadResult.successfulUploads) do
                        -- Encontrar la foto original correspondiente
                        if photos[i] then
                            photos[i]:setPropertyForPlugin(_PLUGIN, 'photorekaanalyzed', true)
                            table.insert(markedPhotos, photos[i])
                            log:info("✓ Foto " .. tostring(i) .. " marcada como analizada")
                        end
                    end
                end)
                log:info("Fotos marcadas correctamente")
                
                -- Invalidar caché centralizado para incluir las nuevas fotos
                local AnalyzedPhotosCache = require 'AnalyzedPhotosCache'
                AnalyzedPhotosCache.invalidate()
                
                -- Actualizar la colección Photoreka automáticamente (incremental, rápido)
                log:info("Actualizando colección Photoreka...")
                PhotorekaCatalogService.updateCollection(markedPhotos)
                log:info("Colección actualizada")
            end
            
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
                local linkText, linkPath
                if onlyToLightbox then
                    linkText = '🔎 Review your photos here before processing'
                    linkPath = '/sync-area#upload'
                else
                    linkText = '🔎 Monitor processing here'
                    linkPath = '/sync-area#processing'
                end
                
                local handoffToken = ApiService.createHandoff()
                local linkUrl = Config.APP_BASE_URL .. linkPath
                if handoffToken then
                    linkUrl = linkUrl .. '?lr_handoff=' .. handoffToken
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
                title = 'Analyze Photos',
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
end)
