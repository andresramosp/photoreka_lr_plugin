-- AnalyzedPhotosCache.lua - Caché centralizado de fotos analizadas por Photoreka
-- Este servicio mantiene un caché de todas las fotos con photorekaanalyzed=true
-- y puede ser usado por SearchMatchService, PhotorekaCatalogService, etc.

local LrLogger = import 'LrLogger'

local AnalyzedPhotosCache = {}

-- Configurar logger
local log = LrLogger('PhotorekaPlugin')
log:enable("logfile")

-- ============================================
-- ESTRUCTURA DEL CACHÉ
-- ============================================
local cache = {
    photos = nil,                 -- Array de fotos analizadas
    byLocalIdentifier = nil,      -- Hash: localIdentifier -> photo (para búsquedas rápidas)
    photoCount = 0,               -- Número de fotos en caché
    catalogPhotoCount = 0,        -- Total de fotos en catálogo (para detectar cambios)
    isValid = false               -- Flag de validez del caché
}

-- ============================================
-- FUNCIONES PÚBLICAS
-- ============================================

-- Invalida el caché (llamar cuando se procesen nuevas fotos)
function AnalyzedPhotosCache.invalidate()
    log:info("[AnalyzedPhotosCache] Caché invalidado")
    cache.isValid = false
    cache.photos = nil
    cache.byLocalIdentifier = nil
    cache.photoCount = 0
end

-- Verifica si el caché está válido para el catálogo dado
-- IMPORTANTE: Debe ser llamada desde dentro de withReadAccessDo
function AnalyzedPhotosCache.isValid(catalog)
    if not cache.isValid then
        return false
    end
    
    local allCatalogPhotos = catalog:getAllPhotos()
    return cache.catalogPhotoCount == #allCatalogPhotos
end

-- Construye o actualiza el caché de fotos analizadas
-- Parámetros:
--   catalog: catálogo de Lightroom
--   progressCallback (opcional): función(current, total, caption) para reportar progreso
-- Retorna: true si el caché fue reconstruido, false si ya estaba válido
-- IMPORTANTE: Esta función DEBE ser llamada desde dentro de withReadAccessDo
function AnalyzedPhotosCache.buildOrUpdate(catalog, progressCallback)
    -- Obtener conteo total del catálogo para detectar cambios
    local allCatalogPhotos = catalog:getAllPhotos()
    local totalCatalogPhotos = #allCatalogPhotos
    
    -- Verificar si el caché sigue siendo válido
    if cache.isValid and cache.catalogPhotoCount == totalCatalogPhotos then
        log:info(string.format("[AnalyzedPhotosCache] ✓ Usando caché existente (%d fotos analizadas)", cache.photoCount))
        return false
    end
    
    -- Caché inválido o desactualizado - reconstruir
    log:info("[AnalyzedPhotosCache] Construyendo caché de fotos analizadas...")
    local startTime = os.clock()
    
    -- Filtrar solo fotos con photorekaanalyzed=true y construir índices
    local photos = {}
    local byId = {}
    local analyzedCount = 0
    local sampleLogged = false
    
    for i, photo in ipairs(allCatalogPhotos) do
        local isAnalyzed = photo:getPropertyForPlugin(_PLUGIN, 'photorekaanalyzed')
        
        -- DEBUG: Mostrar una muestra de lo que se está encontrando
        if not sampleLogged and i <= 5 then
            log:info(string.format("[AnalyzedPhotosCache] SAMPLE photo[%d]: localId=%s, analyzed=%s", 
                i, tostring(photo.localIdentifier), tostring(isAnalyzed)))
            if i == 5 then sampleLogged = true end
        end
        
        if isAnalyzed == true then
            analyzedCount = analyzedCount + 1
            table.insert(photos, photo)
            if photo.localIdentifier then
                byId[tostring(photo.localIdentifier)] = photo
            end
        end
        
        -- Reportar progreso cada 100 fotos para no saturar
        if progressCallback and (i % 100 == 0 or i == totalCatalogPhotos) then
            progressCallback(i, totalCatalogPhotos, string.format('Building Catalog (first time may take a while) (%d/%d)...', i, totalCatalogPhotos))
        end
    end
    
    log:info(string.format("[AnalyzedPhotosCache] Encontradas %d fotos analizadas de %d totales", analyzedCount, totalCatalogPhotos))
    
    -- Actualizar caché
    cache.photos = photos
    cache.byLocalIdentifier = byId
    cache.photoCount = analyzedCount
    cache.catalogPhotoCount = totalCatalogPhotos
    cache.isValid = true
    
    local elapsed = os.clock() - startTime
    log:info(string.format("[AnalyzedPhotosCache] ✓ Caché construido en %.3f segundos", elapsed))
    
    return true
end

-- Obtiene todas las fotos analizadas (array)
-- IMPORTANTE: Llamar buildOrUpdate primero si no se está seguro de que el caché es válido
function AnalyzedPhotosCache.getPhotos()
    return cache.photos or {}
end

-- Obtiene el hash de fotos por localIdentifier (para búsquedas rápidas)
-- IMPORTANTE: Llamar buildOrUpdate primero si no se está seguro de que el caché es válido
function AnalyzedPhotosCache.getByLocalIdentifier()
    return cache.byLocalIdentifier or {}
end

-- Obtiene una foto específica por su localIdentifier
-- Retorna: la foto o nil si no se encuentra
function AnalyzedPhotosCache.getPhotoById(localIdentifier)
    if not cache.byLocalIdentifier then
        return nil
    end
    return cache.byLocalIdentifier[tostring(localIdentifier)]
end

-- Obtiene el conteo de fotos analizadas en caché
function AnalyzedPhotosCache.getCount()
    return cache.photoCount
end

-- Obtiene información del estado del caché (para debug)
function AnalyzedPhotosCache.getStatus()
    return {
        isValid = cache.isValid,
        photoCount = cache.photoCount,
        catalogPhotoCount = cache.catalogPhotoCount
    }
end

return AnalyzedPhotosCache
