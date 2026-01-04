-- PhotorekaCatalogService.lua - Servicio para gestionar la colección de fotos analizadas
local LrApplication = import 'LrApplication'

local AnalyzedPhotosCache = require 'AnalyzedPhotosCache'
local PhotorekaCollectionService = require 'PhotorekaCollectionService'

local PhotorekaCatalogService = {}

local COLLECTION_NAME = "Photoreka - Analyzed Photos"

-- Actualiza la colección con fotos que tienen el metadato marcado
-- Parámetros:
--   newPhotos (opcional): array de fotos recién analizadas para agregar incrementalmente
function PhotorekaCatalogService.updateCollection(newPhotos)
    local catalog = LrApplication.activeCatalog()
    local targetCollection = nil
    local photorekaSet = nil
    
    catalog:withWriteAccessDo('Update Photoreka Catalog', function()
        -- Obtener o crear el collection set "Photoreka" (usando servicio compartido)
        photorekaSet = PhotorekaCollectionService.getOrCreateSet(catalog)

        -- Buscar o crear la colección
        local allCollections = catalog:getChildCollections()
        for _, collection in ipairs(allCollections) do
            if collection:getName() == COLLECTION_NAME then
                targetCollection = collection
                break
            end
        end
        
        if not targetCollection then
            targetCollection = catalog:createCollection(COLLECTION_NAME, photorekaSet, true)
        end

        -- Si se proporcionan fotos nuevas, agregarlas incrementalmente (RÁPIDO)
        if newPhotos and #newPhotos > 0 then
            targetCollection:addPhotos(newPhotos)
        end
    end)
    
    return targetCollection
end

-- Reconstruye completamente la colección (útil para la primera vez o para sincronizar)
-- Parámetros:
--   progressCallback (opcional): función(current, total, caption) para reportar progreso
function PhotorekaCatalogService.rebuildCollection(progressCallback)
    local catalog = LrApplication.activeCatalog()
    local targetCollection = nil
    local photorekaSet = nil
    local analyzedPhotos = {}

    -- FASE DE LECTURA: usar caché centralizado para obtener fotos analizadas
    catalog:withReadAccessDo(function()
        -- Construir/actualizar caché con reporte de progreso
        AnalyzedPhotosCache.buildOrUpdate(catalog, progressCallback)
        -- Obtener las fotos del caché
        analyzedPhotos = AnalyzedPhotosCache.getPhotos()
    end)

    -- FASE DE ESCRITURA: crear/actualizar colección
    if progressCallback then
        progressCallback(1, 1, string.format('Updating collection (%d photos found)...', #analyzedPhotos))
    end
    
    catalog:withWriteAccessDo('Update Photoreka Catalog', function()
        -- Obtener o crear el collection set "Photoreka" (usando servicio compartido)
        photorekaSet = PhotorekaCollectionService.getOrCreateSet(catalog)

        -- Buscar o crear la colección
        local allCollections = catalog:getChildCollections()
        for _, collection in ipairs(allCollections) do
            if collection:getName() == COLLECTION_NAME then
                targetCollection = collection
                break
            end
        end
        
        if not targetCollection then
            targetCollection = catalog:createCollection(COLLECTION_NAME, photorekaSet, true)
        end

        -- Reconstruir completamente la colección
        targetCollection:removeAllPhotos()
        if #analyzedPhotos > 0 then
            targetCollection:addPhotos(analyzedPhotos)
        end
    end)
    
    return targetCollection
end

-- Activa la colección en Lightroom
function PhotorekaCatalogService.activateCollection()
    local catalog = LrApplication.activeCatalog()
    local targetCollection = nil
    
    catalog:withReadAccessDo(function()
        local allCollections = catalog:getChildCollections()
        for _, collection in ipairs(allCollections) do
            if collection:getName() == COLLECTION_NAME then
                targetCollection = collection
                break
            end
        end
    end)
    
    if targetCollection then
        catalog:setActiveSources({ targetCollection })
    end
end

return PhotorekaCatalogService
