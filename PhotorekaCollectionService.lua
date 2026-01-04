-- PhotorekaCollectionService.lua - Servicio compartido para gestionar el collection set "Photoreka"
local LrLogger = import 'LrLogger'

local PhotorekaCollectionService = {}

local COLLECTION_SET_NAME = "Photoreka"

-- Configurar logger
local log = LrLogger('PhotorekaPlugin')
log:enable("logfile")

-- Obtiene o crea el collection set "Photoreka"
-- Parámetros:
--   catalog: catálogo de Lightroom
-- Retorna: el collection set "Photoreka"
-- IMPORTANTE: Debe ser llamado desde dentro de withWriteAccessDo
function PhotorekaCollectionService.getOrCreateSet(catalog)
    local photorekSet = nil
    
    -- Buscar si ya existe
    for _, set in ipairs(catalog:getChildCollectionSets()) do
        if set:getName() == COLLECTION_SET_NAME then
            photorekSet = set
            log:info("Collection set 'Photoreka' encontrado")
            return photorekSet
        end
    end
    
    -- Si no existe, crearlo
    photorekSet = catalog:createCollectionSet(COLLECTION_SET_NAME)
    log:info("Collection set 'Photoreka' creado")
    
    return photorekSet
end

-- Nombre del collection set
function PhotorekaCollectionService.getSetName()
    return COLLECTION_SET_NAME
end

return PhotorekaCollectionService
