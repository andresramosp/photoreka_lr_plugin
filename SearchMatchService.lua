-- SearchMatchService.lua - Servicio de matcheo de fotos entre API y catálogo de Lightroom
-- VERSIÓN SIMPLIFICADA: Solo búsqueda por uniqueId (localIdentifier)
local LrLogger = import 'LrLogger'

local SearchMatchService = {}

-- Configurar logger
local log = LrLogger('PhotorekaPlugin')
log:enable("logfile")

-- ============================================
-- SISTEMA DE CACHÉ
-- ============================================
-- Caché global que persiste entre búsquedas en la misma sesión
-- Solo incluye fotos que tienen photorekaanalyzed=true
local photoCache = {
    byLocalIdentifier = nil,      -- Hash: localIdentifier -> photo
    photoCount = 0,               -- Número de fotos en caché
    catalogPhotoCount = 0,        -- Total de fotos en catálogo (para detectar cambios)
    isValid = false               -- Flag de validez del caché
}

-- Invalida el caché (llamar cuando se procesen nuevas fotos)
function SearchMatchService.invalidateCache()
    log:info("Caché de búsqueda invalidado")
    photoCache.isValid = false
    photoCache.byLocalIdentifier = nil
    photoCache.photoCount = 0
end

-- Construye o actualiza el caché de fotos analizadas
-- Parámetros:
--   catalog: catálogo de Lightroom
-- Retorna: true si el caché fue construido, false si ya estaba válido
-- IMPORTANTE: Esta función DEBE ser llamada desde dentro de withReadAccessDo
local function buildOrUpdateCache(catalog)
    -- Obtener conteo total del catálogo para detectar cambios
    local allCatalogPhotos = catalog:getAllPhotos()
    local totalCatalogPhotos = #allCatalogPhotos
    
    -- Verificar si el caché sigue siendo válido
    if photoCache.isValid and photoCache.catalogPhotoCount == totalCatalogPhotos then
        log:info(string.format("✓ Usando caché existente (%d fotos analizadas)", photoCache.photoCount))
        return false
    end
    
    -- Caché inválido o desactualizado - reconstruir
    log:info("Construyendo caché de fotos analizadas...")
    local startTime = os.clock()
    
    -- Filtrar solo fotos con photorekaanalyzed=true y construir índice
    local byId = {}
    local analyzedCount = 0
    
    for _, photo in ipairs(allCatalogPhotos) do
        local isAnalyzed = photo:getPropertyForPlugin(_PLUGIN, 'photorekaanalyzed')
        if isAnalyzed == true then
            analyzedCount = analyzedCount + 1
            if photo.localIdentifier then
                byId[tostring(photo.localIdentifier)] = photo
            end
        end
    end
    
    log:info(string.format("Encontradas %d fotos analizadas de %d totales", analyzedCount, totalCatalogPhotos))
    
    -- Actualizar caché
    photoCache.byLocalIdentifier = byId
    photoCache.photoCount = analyzedCount
    photoCache.catalogPhotoCount = totalCatalogPhotos
    photoCache.isValid = true
    
    local elapsed = os.clock() - startTime
    log:info(string.format("✓ Caché construido en %.3f segundos", elapsed))
    
    return true
end

-- FUNCIÓN PRINCIPAL: Busca fotos en Lightroom por uniqueId
-- Parámetros:
--   catalog: catálogo de Lightroom
--   searchData: array de tablas {uniqueId, fileName, apiPhoto, totalScore}
-- Retorna: array de fotos encontradas (en el mismo orden que searchData)
-- IMPORTANTE: Esta función DEBE ser llamada desde dentro de withReadAccessDo
function SearchMatchService.findPhotos(catalog, searchData)
    log:info("========================================")
    log:info("INICIANDO BÚSQUEDA DE FOTOS POR UNIQUEID")
    log:info("Total fotos a buscar: " .. tostring(#searchData))
    log:info("========================================")
    
    -- Construir o actualizar caché
    buildOrUpdateCache(catalog)
    
    local foundPhotos = {}
    local foundSet = {}  -- Para evitar duplicados
    local stats = {
        found = 0,
        notFound = 0,
        noUniqueId = 0
    }
    
    -- Procesar cada foto de searchData
    for i, data in ipairs(searchData) do
        if data.uniqueId then
            local uniqueIdStr = tostring(data.uniqueId)
            local photo = photoCache.byLocalIdentifier[uniqueIdStr]
            
            if photo then
                local photoKey = tostring(photo.localIdentifier)
                if not foundSet[photoKey] then
                    table.insert(foundPhotos, photo)
                    foundSet[photoKey] = true
                    stats.found = stats.found + 1
                    log:info(string.format("[%d] ✓ Encontrada: %s", i, uniqueIdStr))
                end
            else
                stats.notFound = stats.notFound + 1
                log:info(string.format("[%d] ✗ No encontrada: %s", i, uniqueIdStr))
            end
        else
            stats.noUniqueId = stats.noUniqueId + 1
            log:info(string.format("[%d] ✗ Sin uniqueId", i))
        end
    end
    
    -- Resumen
    log:info("========================================")
    log:info("RESUMEN:")
    log:info(string.format("  - Encontradas: %d", stats.found))
    log:info(string.format("  - No encontradas: %d", stats.notFound))
    log:info(string.format("  - Sin uniqueId: %d", stats.noUniqueId))
    log:info(string.format("  - TOTAL: %d de %d", #foundPhotos, #searchData))
    log:info("========================================")
    
    return foundPhotos
end

return SearchMatchService
