-- Search.lua - Búsqueda semántica en el catálogo de Photoreka
local LrTasks = import 'LrTasks'
local LrApplication = import 'LrApplication'
local LrDialogs = import 'LrDialogs'
local LrView = import 'LrView'
local LrBinding = import 'LrBinding'
local LrFunctionContext = import 'LrFunctionContext'
local LrLogger = import 'LrLogger'

-- Configurar logger
local log = LrLogger('PhotorekaPlugin')
log:enable("logfile")

-- Servicios personalizados
local Config = require 'Config'
local ApiService = require 'ApiService'
local AuthService = require 'AuthService'
local SearchMatchService = require 'SearchMatchService'

log:info("========================================")
log:info("SEARCH.LUA EJECUTÁNDOSE")
log:info("========================================")

-- Función para crear o actualizar una colección con los resultados
-- Parámetros:
--   catalog: catálogo de Lightroom
--   collectionName: nombre de la colección
--   photos: array de fotos a añadir (ya ordenado por relevancia)
-- Retorna: la colección creada/actualizada
local function createOrUpdateCollection(catalog, collectionName, photos)
    local collection = nil
    
    catalog:withWriteAccessDo("Create Search Results Collection", function()
        -- Buscar si ya existe la colección
        local collections = catalog:getChildCollections()
        for _, coll in ipairs(collections) do
            if coll:getName() == collectionName then
                collection = coll
                log:info("Colección encontrada: " .. collectionName)
                break
            end
        end
        
        -- Si no existe, crearla
        if not collection then
            collection = catalog:createCollection(collectionName)
            log:info("Colección creada: " .. collectionName)
        end
        
        -- Limpiar la colección (remover fotos anteriores)
        collection:removeAllPhotos()
        log:info("Colección limpiada")
        
        -- Añadir las nuevas fotos
        if #photos > 0 then
            collection:addPhotos(photos)
            log:info(tostring(#photos) .. " fotos añadidas a la colección")
            
            -- TODO: Ordenamiento deshabilitado temporalmente para debug
            -- collection:setPhotoOrder(photos)
            -- log:info("Orden personalizado aplicado a la colección (por relevancia)")
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
    props.precisionLevel = 2  -- Por defecto: flexible (1=strict, 2=flexible, 3=broad)
    
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
                width = 200,
            },
            
            f:spacer { width = 10 },
            
            f:static_text {
                title = LrView.bind {
                    key = 'precisionLevel',
                    transform = function(value)
                        if value == 1 then
                            return 'Strict (excellent only)'
                        elseif value == 2 then
                            return 'Flexible (excellent + good)'
                        else
                            return 'Broad (all except poor)'
                        end
                    end
                },
                font = '<system/small>',
            },
        },
    }
    
    -- Mostrar el diálogo
    local result = LrDialogs.presentModalDialog({
        title = 'Photoreka Search',
        contents = dialogContent,
        actionVerb = 'Search',
        cancelVerb = 'Cancel',
    })
    
    -- Si el usuario hace clic en "Search"
    if result == 'ok' then
        local searchQuery = props.searchQuery
        local precisionLevel = props.precisionLevel
        
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
            
            -- Realizar búsqueda
            local searchResults = nil
            
            LrFunctionContext.callWithContext('searchPhotos', function(searchContext)
                local progressScope = LrDialogs.showModalProgressDialog({
                    title = 'Searching...',
                    caption = 'Performing semantic search in your Photoreka catalog...',
                    functionContext = searchContext,
                })
                
                -- Llamar a la API de búsqueda
                local success, result = LrTasks.pcall(function()
                    return ApiService.search(searchQuery)
                end)
                
                progressScope:done()
                
                if not success then
                    log:error("Error en búsqueda: " .. tostring(result))
                    LrDialogs.message(
                        'Photoreka Search',
                        'Search failed: ' .. tostring(result),
                        'error'
                    )
                    return
                end
                
                searchResults = result
            end)
            
            if not searchResults then
                return
            end
            
            log:info("========== SEARCH RESULTS DEBUG ==========")
            log:info("RAW API RESPONSE:")
            log:info(require('JSON').encode(searchResults))
            log:info("==========================================")
            log:info("Type: " .. tostring(searchResults.type))
            log:info("Has data: " .. tostring(searchResults.data ~= nil))
            
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
                
                -- Filtrar según el nivel de precisión
                local shouldInclude = false
                if labelScore then
                    if precisionLevel == 1 then
                        -- Strict: solo excellent
                        shouldInclude = (labelScore == "excellent")
                    elseif precisionLevel == 2 then
                        -- Flexible: excellent + good
                        shouldInclude = (labelScore == "excellent" or labelScore == "good")
                    else
                        -- Broad: todo menos poor
                        shouldInclude = (labelScore ~= "poor")
                    end
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
            -- TODO: Ordenamiento deshabilitado temporalmente para debug
            -- table.sort(searchData, function(a, b)
            --     return (a.totalScore or 0) > (b.totalScore or 0)
            -- end)
            -- log:info("Resultados ordenados por totalScore (relevancia)")
            
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
                        photos = SearchMatchService.findPhotos(catalog, searchData)
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
            local collectionName = "Photoreka Search: " .. searchQuery
            local collection = createOrUpdateCollection(catalog, collectionName, foundPhotos)
            
            -- Abrir la colección automáticamente
            if collection then
                catalog:setActiveSources({ collection })
                log:info("Colección activada en el catálogo")
            end
            
            -- Mostrar mensaje de éxito
            LrDialogs.message(
                'Photoreka Search',
                string.format('Found %d photos matching "%s".\n\nResults saved to collection:\n"%s"', 
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
