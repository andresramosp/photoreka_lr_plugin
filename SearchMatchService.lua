-- SearchMatchService.lua - Servicio de matcheo de fotos entre API y catálogo de Lightroom
-- VERSIÓN SIMPLIFICADA: Solo búsqueda por uniqueId (localIdentifier)
local LrLogger = import 'LrLogger'

local AnalyzedPhotosCache = require 'AnalyzedPhotosCache'

local SearchMatchService = {}

-- Configurar logger
local log = LrLogger('PhotorekaPlugin')
log:enable("logfile")

-- Invalida el caché (delega al servicio centralizado)
function SearchMatchService.invalidateCache()
    AnalyzedPhotosCache.invalidate()
end

-- FUNCIÓN PRINCIPAL: Busca fotos en Lightroom por uniqueId
-- Parámetros:
--   catalog: catálogo de Lightroom
--   searchData: array de tablas {uniqueId, fileName, apiPhoto, totalScore}
--   progressCallback (opcional): función(current, total, caption) para reportar progreso
-- Retorna: array de fotos encontradas (en el mismo orden que searchData)
-- IMPORTANTE: Esta función DEBE ser llamada desde dentro de withReadAccessDo
function SearchMatchService.findPhotos(catalog, searchData, progressCallback)
    log:info("========================================")
    log:info("INICIANDO BÚSQUEDA DE FOTOS POR UNIQUEID")
    log:info("Total fotos a buscar: " .. tostring(#searchData))
    log:info("========================================")
    
    -- Construir o actualizar caché centralizado con reporte de progreso
    AnalyzedPhotosCache.buildOrUpdate(catalog, progressCallback)
    
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
            local photo = AnalyzedPhotosCache.getPhotoById(uniqueIdStr)
            
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
