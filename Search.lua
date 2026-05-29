-- Search.lua - Búsqueda semántica en el catálogo de Photoreka
local LrTasks = import 'LrTasks'
local LrApplication = import 'LrApplication'
local LrDialogs = import 'LrDialogs'
local LrView = import 'LrView'
local LrBinding = import 'LrBinding'
local LrFunctionContext = import 'LrFunctionContext'
local LrLogger = import 'LrLogger'
local LrHttp = import 'LrHttp'

-- Configurar logger
local log = LrLogger('PhotorekaPlugin')
log:enable("logfile")

-- Servicios personalizados
local Config = require 'Config'
local ApiService = require 'ApiService'
local AuthService = require 'AuthService'
local SearchMatchService = require 'SearchMatchService'
local PhotorekaCollectionService = require 'PhotorekaCollectionService'

log:info("========================================")
log:info("SEARCH.LUA EJECUTÁNDOSE")
log:info("========================================")

-- Función para mapear labelScore a Label (color)
local function labelScoreToColor(labelScore)
    if labelScore == "excellent" then return "green"
    elseif labelScore == "good" then return "yellow"
    elseif labelScore == "fair" then return "blue"
    elseif labelScore == "poor" then return "red"
    else return nil end
end

-- Función para crear o actualizar una colección con los resultados
-- Parámetros:
--   catalog: catálogo de Lightroom
--   collectionName: nombre de la colección
--   photos: array de fotos a añadir (ya ordenado por relevancia)
--   searchData: array con información de scores para cada foto
--   useColorLabels: boolean - si se deben aplicar color labels
-- Retorna: la colección creada/actualizada
local function createOrUpdateCollection(catalog, collectionName, photos, searchData, useColorLabels)
    local collection = nil
    
    -- TRANSACCIÓN 0: Asegurar que existe el collection set "Photoreka"
    -- Esto debe hacerse en una transacción separada para que Lightroom lo registre
    local setExists = false
    catalog:withWriteAccessDo("Ensure Photoreka Set Exists", function()
        local collectionSets = catalog:getChildCollectionSets()
        for _, set in ipairs(collectionSets) do
            if set:getName() == "Photoreka" then
                setExists = true
                break
            end
        end
        
        if not setExists then
            catalog:createCollectionSet("Photoreka")
            log:info("Collection set 'Photoreka' creado en transacción separada")
        end
    end)
    
    -- Si acabamos de crear el set, dar tiempo a Lightroom para procesarlo
    if not setExists then
        LrTasks.sleep(0.1)
    end
    
    -- TRANSACCIÓN 1: Limpiar colecciones anteriores
    catalog:withWriteAccessDo("Cleanup Previous Search Collections", function()
        local photorekaSet = PhotorekaCollectionService.getOrCreateSet(catalog)
        
        -- Buscar y eliminar cualquier colección de búsqueda anterior (empieza con "Photoreka Search -")
        local collections = photorekaSet:getChildCollections()
        
        for _, coll in ipairs(collections) do
            local collName = coll:getName()
            if collName:find("^Photoreka Search %-") then
                log:info("Eliminando colección de búsqueda anterior: " .. collName)
                coll:delete()
            end
        end
    end)
    
    -- TRANSACCIÓN 2: Crear la nueva colección y añadir fotos
    catalog:withWriteAccessDo("Create Search Collection", function()
        -- Re-obtener el collection set (la referencia puede haber cambiado)
        local photorekaSet = PhotorekaCollectionService.getOrCreateSet(catalog)
        
        -- Crear la nueva colección dentro del set Photoreka
        -- El tercer parámetro 'true' permite usar la colección inmediatamente
        collection = catalog:createCollection(collectionName, photorekaSet, true)
        log:info("Nueva colección creada: " .. collectionName .. " (dentro de Photoreka)")
        
        -- Añadir las fotos
        if #photos > 0 then
            collection:addPhotos(photos)
            log:info(tostring(#photos) .. " fotos añadidas a la colección")
            
            -- PASO 1: Limpiar color labels anteriores de fotos marcadas por el plugin
            -- Esto se hace SIEMPRE, independientemente de useColorLabels
            local cleanedCount = 0
            for i, photo in ipairs(photos) do
                local hasPluginMetadata = photo:getPropertyForPlugin(_PLUGIN, 'photorekasearchmetadata')
                if hasPluginMetadata then
                    -- Esta foto fue marcada anteriormente por el plugin, limpiar su label
                    photo:setRawMetadata("colorNameForLabel", "")
                    -- Quitar el metadato de marcado
                    photo:setPropertyForPlugin(_PLUGIN, 'photorekasearchmetadata', false)
                    cleanedCount = cleanedCount + 1
                end
            end
            if cleanedCount > 0 then
                log:info(string.format("%d color labels anteriores limpiados", cleanedCount))
            end
            
            -- PASO 2: Aplicar nuevos color labels solo si useColorLabels está activado
            if useColorLabels then
                local appliedCount = 0
                for i, photo in ipairs(photos) do
                    -- Buscar el searchData correspondiente a esta foto
                    local photoData = searchData[i]
                    if photoData and photoData.apiPhoto then
                        local labelScore = photoData.apiPhoto.labelScore
                        
                        -- Aplicar Label basado en labelScore
                        local colorLabel = labelScoreToColor(labelScore)
                        if colorLabel then
                            photo:setRawMetadata("colorNameForLabel", colorLabel)
                            -- Marcar esta foto con el metadato del plugin
                            photo:setPropertyForPlugin(_PLUGIN, 'photorekasearchmetadata', true)
                            appliedCount = appliedCount + 1
                            
                            log:info(string.format("Foto %d: Label=%s (totalScore=%.3f, labelScore=%s)", 
                                i, colorLabel, 
                                photoData.totalScore or 0, labelScore or "none"))
                        end
                    end
                end
                log:info(string.format("%d color labels aplicados", appliedCount))
            else
                log:info("Color labels no aplicados (opción desactivada)")
            end
        end
    end)
    
    return collection
end

-- Envolver en async task
LrTasks.startAsyncTask(function()
LrFunctionContext.callWithContext('showSearchDialog', function(context)
    
    local catalog = LrApplication.activeCatalog()
    local f = LrView.osFactory()
    
    -- Crear propiedades observables
    local props = LrBinding.makePropertyTable(context)
    props.searchQuery = ""
    props.isSearching = false
    -- props.precisionLevel = 2  -- Por defecto: relaxed (1=relaxed, 2=fair, 3=strict)
    props.searchMode = "adaptive"  -- Por defecto: adaptive (opciones: broad, adaptive, precise)
    props.useColorLabels = false  -- Por defecto: no aplicar color labels
    
    -- Observer para el checkbox de useColorLabels
    props:addObserver('useColorLabels', function(properties, key, newValue)
        -- Solo mostrar confirmación cuando se marca (true), no cuando se desmarca
        if newValue == true then
            local confirmResult = LrDialogs.confirm(
                'This will modify color labels on your original photos.',
                'Photos will be marked with color labels based on search relevance:\n\n• Green = Excellent match\n• Yellow = Good match\n• Blue = Fair match.\n\nDo you want to continue?',
                'Continue',
                'Cancel'
            )
            
            if confirmResult == 'cancel' then
                -- Desmarcar el checkbox si cancela
                props.useColorLabels = false
                log:info("Usuario canceló la activación de color labels")
            else
                log:info("Usuario confirmó el uso de color labels")
            end
        end
    end)
    
    -- Obtener información del usuario autenticado
    local userInfo = AuthService.getStoredUserInfo()
    local accountButtonTitle = userInfo and string.format('👤 %s', userInfo.name or userInfo.email) or '👤 Cuenta'
    
    -- Crear el contenido del diálogo
    local dialogContent = f:column {
        bind_to_object = props,
        spacing = f:control_spacing(),
        
        -- Header
        f:row {
            fill_horizontal = 1,
            
            f:static_text {
                title = 'Semantic Search',
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
        
        -- Descripción
        f:static_text {
            title = 'Search for photos in your Photoreka catalog using natural language.',
            font = '<system/small>',
        },
        
        f:spacer { height = 10 },
        
        -- Input de búsqueda
        f:row {
            fill_horizontal = 1,
            spacing = f:control_spacing(),
            
            f:static_text {
                title = 'Search:',
                width = 60,
            },
            
            f:edit_field {
                fill_horizontal = 1,
                value = LrView.bind('searchQuery'),
                width_in_chars = 50,
                immediate = true,
            },
        },
        
        f:spacer { height = 5 },
        
        -- Ejemplos
        f:static_text {
            title = 'Examples: "sunset beach", "people walking", "red flowers"',
            font = '<system/small>',
        },
        
        f:spacer { height = 15 },
        
        --[[ SLIDER DE PRECISIÓN (COMENTADO - Reemplazado por radio buttons)
        -- Slider de precisión
        f:row {
            fill_horizontal = 1,
            
            f:static_text {
                title = 'Precision:',
                width = 60,
            },
            
            f:slider {
                value = LrView.bind('precisionLevel'),
                min = 1,
                max = 3,
                integral = true,
                value_step = 1,
                width = 200,
            },
            
            f:spacer { width = 10 },
            
            f:static_text {
                title = LrView.bind {
                    key = 'precisionLevel',
                    transform = function(value)
                        if value == 1 then
                            return 'Relaxed'
                        elseif value == 2 then
                            return 'Fair'
                        elseif value == 3 then
                            return 'Strict'
                        end
                    end
                },
                font = '<system/small>',
                width = 80,
            },
        },
        --]]
        
        -- Radio buttons para Search Mode
        f:row {
            fill_horizontal = 1,
            spacing = f:control_spacing(),
            
            f:static_text {
                title = 'Mode:',
                width = 80,
            },
            
            f:radio_button {
                title = 'Fast',
                value = LrView.bind('searchMode'),
                checked_value = 'broad',
            },
            
            f:radio_button {
                title = 'Adaptive',
                value = LrView.bind('searchMode'),
                checked_value = 'adaptive',
            },
            
            f:radio_button {
                title = 'Precise',
                value = LrView.bind('searchMode'),
                checked_value = 'precise',
            },
        },
        
        f:spacer { height = 10 },
        
        -- Checkbox para usar color labels
        f:row {
            fill_horizontal = 1,
            spacing = f:control_spacing(),
            
            f:checkbox {
                title = 'Use color labels',
                value = LrView.bind('useColorLabels'),
            },
        },
    }
    
    -- Mostrar el diálogo
    local result = LrDialogs.presentModalDialog({
        title = 'Photoreka Search',
        contents = dialogContent,
        actionVerb = 'Search',
        cancelVerb = 'Cancel',
        otherVerb = '🌐 Photoreka Search',
    })
    
    -- Si el usuario hace clic en "Advanced search"
    if result == 'other' then
        local handoffToken = ApiService.createHandoff()
        local url = Config.APP_BASE_URL .. '/search'
        if handoffToken then
            url = url .. '?lr_handoff=' .. handoffToken
        end
        LrHttp.openUrlInBrowser(url)
        return
    end
    
    -- Si el usuario hace clic en "Search"
    if result == 'ok' then
        local searchQuery = props.searchQuery
        -- local precisionLevel = props.precisionLevel  -- COMENTADO: Reemplazado por searchMode
        local searchMode = props.searchMode
        local useColorLabels = props.useColorLabels
        
        -- Validar que no esté vacío
        if not searchQuery or searchQuery == "" then
            LrDialogs.message(
                'Photoreka Search',
                'Please enter a search query.',
                'info'
            )
            return
        end
        
        -- Ejecutar búsqueda en async task
        LrTasks.startAsyncTask(function()
            log:info("Usuario realizó búsqueda: " .. searchQuery)
            
            -- Verificar autenticación
            local token = AuthService.ensureAuthenticated()
            
            if not token or token == '' then
                log:info("Autenticación cancelada, abortando búsqueda")
                LrDialogs.message(
                    'Photoreka Search',
                    'Search cancelled. You must log in to continue.',
                    'info'
                )
                return
            end

            -- Verificar créditos: se necesitan al menos 2 fotos analizadas para buscar
            local creditsOk, creditsResult = LrTasks.pcall(function()
                return ApiService.getUsage()
            end)
            if creditsOk and creditsResult then
                if (creditsResult.creditsUsed or 0) < 2 then
                    LrDialogs.message(
                        'Photoreka Search',
                        'Insufficient credits to perform search.',
                        'info'
                    )
                    return
                end
            else
                log:warn("Could not verify credits before search: " .. tostring(creditsResult))
            end

            -- Realizar búsqueda
            local searchResults = nil
            
            LrFunctionContext.callWithContext('searchPhotos', function(searchContext)
                local progressScope = LrDialogs.showModalProgressDialog({
                    title = 'Searching...',
                    caption = 'Performing semantic search in your Photoreka catalog...',
                    functionContext = searchContext,
                })
                
                -- Variables compartidas para comunicación entre tasks
                local apiCompleted = false
                local apiSuccess = false
                local apiResult = nil
                
                -- Generar tiempo estimado aleatorio entre 5 y 10 segundos
                local estimatedTime = math.random(5, 10)
                local updateInterval = 0.1  -- Actualizar cada 0.1 segundos
                local totalSteps = estimatedTime / updateInterval
                local currentStep = 0
                
                log:info(string.format("Simulando progreso durante ~%d segundos", estimatedTime))
                
                -- Iniciar la llamada a la API en un async task separado
                LrTasks.startAsyncTask(function()
                    apiSuccess, apiResult = LrTasks.pcall(function()
                        return ApiService.search(searchQuery, searchMode)
                    end)
                    apiCompleted = true
                end)
                
                -- Simular progreso mientras esperamos
                while not apiCompleted and currentStep < totalSteps do
                    currentStep = currentStep + 1
                    local progress = currentStep / totalSteps
                    progressScope:setPortionComplete(progress, 1.0)
                    LrTasks.sleep(updateInterval)
                end
                
                -- Si la API terminó antes del tiempo estimado, completar la barra rápidamente
                if apiCompleted and currentStep < totalSteps then
                    progressScope:setPortionComplete(1.0, 1.0)
                    LrTasks.sleep(0.2)  -- Breve pausa para que se vea la barra completa
                end
                
                -- Si el tiempo se acabó pero la API no terminó, esperar a que termine
                while not apiCompleted do
                    LrTasks.sleep(0.1)
                end
                
                progressScope:done()
                
                if not apiSuccess then
                    log:error("Error en búsqueda: " .. tostring(apiResult))
                    if tostring(apiResult):find("INSUFFICIENT_CREDITS") then
                        LrDialogs.message(
                            'Photoreka Search',
                            'You have no credits remaining.\n\nPlease purchase more credits at app.photoreka.com to continue searching.',
                            'warning'
                        )
                    else
                        LrDialogs.message(
                            'Photoreka Search',
                            'Search failed. Please try again later.',
                            'error'
                        )
                    end
                    return
                end
                
                searchResults = apiResult
            end)
            
            if not searchResults then
                return
            end
            
            log:info("========== SEARCH RESULTS DEBUG ==========")
            -- log:info("RAW API RESPONSE:")
            -- log:info(require('JSON').encode(searchResults))
            -- log:info("==========================================")
            -- log:info("Type: " .. tostring(searchResults.type))
            -- log:info("Has data: " .. tostring(searchResults.data ~= nil))
            
            -- Acceder a data.results (la API devuelve {type, data: {hasMore, results}})
            local data = searchResults.data
            if not data then
                log:error("No 'data' field in search results")
                LrDialogs.message(
                    'Photoreka Search',
                    'Invalid response format from server.',
                    'error'
                )
                return
            end
            
            log:info("Has results: " .. tostring(data.results ~= nil))
            log:info("HasMore: " .. tostring(data.hasMore))
            
            -- results es un objeto con claves numéricas {"1": [...], "2": [...]}
            -- Necesitamos convertirlo a un array plano
            local resultsObject = data.results or {}
            local resultsArray = {}
            
            -- Iterar sobre las claves del objeto
            for iterationKey, iterationResults in pairs(resultsObject) do
                log:info("Processing iteration: " .. tostring(iterationKey) .. " with " .. tostring(#iterationResults) .. " results")
                -- iterationResults es un array de fotos para esta iteración
                for _, photoResult in ipairs(iterationResults) do
                    table.insert(resultsArray, photoResult)
                end
            end
            
            local totalResults = #resultsArray
            
            log:info("Total results flattened: " .. tostring(totalResults))
            log:info("==========================================")
            
            if totalResults == 0 then
                LrDialogs.message(
                    'Photoreka Search',
                    'No results found for: "' .. searchQuery .. '"',
                    'info'
                )
                return
            end
            
            -- Extraer uniqueIds, fileNames y objetos photo de los resultados, filtrando por labelScore
            local searchData = {}
            for i, photoResult in ipairs(resultsArray) do
                local uniqueId = nil
                local fileName = nil
                
                -- Obtener labelScore para filtrado
                local labelScore = photoResult.photo and photoResult.photo.labelScore
                
                --[[ FILTRADO POR PRECISIÓN (COMENTADO - Ahora siempre usa relaxed)
                -- Filtrar según el nivel de precisión
                local shouldInclude = false
                if labelScore then
                    if precisionLevel == 3 then
                        -- Strict: solo excellent
                        shouldInclude = (labelScore == "excellent")
                    elseif precisionLevel == 2 then
                        -- Flexible: excellent + good
                        shouldInclude = (labelScore == "excellent" or labelScore == "good")
                    elseif precisionLevel == 1 then
                        -- Broad: todo menos poor
                        shouldInclude = (labelScore ~= "poor")
                    end
                else
                    -- Si no tiene labelScore, incluir por defecto
                    shouldInclude = true
                end
                --]]
                
                -- Filtrado siempre en modo relaxed (todo menos poor)
                local shouldInclude = false
                if labelScore then
                    shouldInclude = (labelScore ~= "poor")
                else
                    -- Si no tiene labelScore, incluir por defecto
                    shouldInclude = true
                end
                
                -- Solo procesar si pasa el filtro
                if shouldInclude then
                
                -- Obtener originalFileName del objeto photo
                if photoResult.photo and photoResult.photo.originalFileName then
                    fileName = photoResult.photo.originalFileName
                end
                
                -- Extraer uniqueId de descriptions
                if photoResult.photo and photoResult.photo.descriptions then
                    local descriptions = photoResult.photo.descriptions
                    
                    -- Acceder directamente a source
                    if descriptions.source then
                        if descriptions.source.type == "lightroom" and descriptions.source.uniqueId then
                            uniqueId = descriptions.source.uniqueId
                        end
                    end
                end
                
                -- Añadir a searchData si tenemos al menos uno de los dos
                if uniqueId or fileName then
                    -- Capturar totalScore para ordenamiento
                    local totalScore = photoResult.photo and photoResult.photo.totalScore or 0
                    
                    table.insert(searchData, {
                        uniqueId = uniqueId,
                        fileName = fileName,
                        apiPhoto = photoResult.photo,  -- Pasar el objeto completo para EXIF matching
                        totalScore = totalScore  -- Score para ordenar por relevancia
                    })
                end
                
                else
                    -- Foto filtrada por labelScore (solo log si es relevante)
                    if Config.DEBUG_MODE then
                        log:info(string.format("Foto %d filtrada por labelScore: %s", i, tostring(labelScore)))
                    end
                end
            end
            
            log:info("Datos de búsqueda extraídos: " .. tostring(#searchData))
            
            if #searchData == 0 then
                LrDialogs.message(
                    'Photoreka Search',
                    string.format('Found %d results, but none have identifying information (uniqueId or fileName).', totalResults),
                    'info'
                )
                return
            end
            
            -- Ordenar por totalScore (mayor a menor) para que las fotos más relevantes aparezcan primero
            table.sort(searchData, function(a, b)
                return (a.totalScore or 0) > (b.totalScore or 0)
            end)
            log:info("Resultados ordenados por totalScore (relevancia)")
            
            -- Buscar fotos en Lightroom usando el nuevo servicio de matcheo
            -- NOTA: Esto puede tardar 60+ segundos en catálogos grandes (construye caché)
            local foundPhotos = nil
            local matchError = nil
            
            LrFunctionContext.callWithContext('matchPhotos', function(matchContext)
                local matchProgress = LrDialogs.showModalProgressDialog({
                    title = 'Matching photos...',
                    caption = 'Building catalog index (first time may take a while)...',
                    functionContext = matchContext,
                })
                
                local success, result = LrTasks.pcall(function()
                    local photos = nil
                    catalog:withReadAccessDo(function()
                        -- Pasar callback de progreso real
                        photos = SearchMatchService.findPhotos(catalog, searchData, function(current, total, caption)
                            matchProgress:setPortionComplete(current, total)
                            -- Remover el conteo numérico del caption (mantener solo el texto descriptivo)
                            local cleanCaption = caption:gsub("%s*%(%d+/%d+%)%.%.%.$", "...")
                            matchProgress:setCaption(cleanCaption)
                        end)
                    end)
                    return photos
                end)
                
                matchProgress:done()
                
                if success then
                    foundPhotos = result
                else
                    matchError = tostring(result)
                    log:error("Error en matcheo: " .. matchError)
                end
            end)
            
            if matchError then
                LrDialogs.message(
                    'Photoreka Search',
                    'Error matching photos: ' .. matchError,
                    'error'
                )
                return
            end
            
            if not foundPhotos or #foundPhotos == 0 then
                LrDialogs.message(
                    'Photoreka Search',
                    string.format('Found %d results, but none could be located in your Lightroom catalog.', totalResults),
                    'warning'
                )
                return
            end
            
            -- Crear colección con los resultados (el orden ya se aplica dentro)
            -- Mapear searchMode a nombre legible
            local searchModeLabel = searchMode
            if searchMode == "broad" then
                searchModeLabel = "Fast"
            elseif searchMode == "adaptive" then
                searchModeLabel = "Adaptive"
            elseif searchMode == "precise" then
                searchModeLabel = "Precise"
            end
            local collectionName = "Photoreka Search - " .. searchModeLabel .. ": " .. searchQuery
            
            -- Desactivar la colección si ya está activa (para evitar problemas al limpiarla)
            catalog:withWriteAccessDo("Deactivate collection", function()
                local activeSources = catalog:getActiveSources()
                if activeSources and #activeSources > 0 then
                    for _, source in ipairs(activeSources) do
                        if source.getName and source:getName() == collectionName then
                            catalog:setActiveSources({})
                            log:info("Colección desactivada antes de actualizar")
                            break
                        end
                    end
                end
            end)
            
            local collection = createOrUpdateCollection(catalog, collectionName, foundPhotos, searchData, useColorLabels)
            
            -- Abrir la colección automáticamente
            -- IMPORTANTE: Primero desactivamos todas las sources, esperamos un momento,
            -- y luego activamos la colección para forzar que Lightroom haga scroll al inicio
            if collection then
                catalog:setActiveSources({})
                log:info("Todas las sources desactivadas antes de activar la colección")
                
                -- Pequeño delay para permitir que Lightroom procese la desactivación
                LrTasks.sleep(0.1)
                
                catalog:setActiveSources({ collection })
                log:info("Colección activada en el catálogo")
            end
            
            -- Mostrar mensaje de éxito con recomendación de ordenación
            LrDialogs.message(
                'Photoreka Search',
                string.format('Found %d photos matching "%s".\n\nResults saved to collection:\n"%s"\n\n💡 TIP: Sort by \'Custom Order\' to see results ordered by relevance.', 
                    #foundPhotos, 
                    searchQuery, 
                    collectionName
                ),
                'info'
            )
            
            log:info("Búsqueda completada exitosamente")
        end)
    end
    
end)
end)
