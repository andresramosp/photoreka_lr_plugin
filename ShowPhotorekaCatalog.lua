

local LrHttp = import 'LrHttp'
local LrTasks = import 'LrTasks'

-- LrTasks.startAsyncTask(function()
--     LrHttp.openUrlInBrowser("https://app.photoreka.com/photo-hub#catalog")
-- end)


-- ShowPhotorekaCatalog.lua - Muestra colección de fotos analizadas por Photoreka
local LrTasks = import 'LrTasks'
local LrDialogs = import 'LrDialogs'
local LrFunctionContext = import 'LrFunctionContext'
local LrApplication = import 'LrApplication'
local LrLogger = import 'LrLogger'

local PhotorekaCatalogService = require 'PhotorekaCatalogService'

-- Configurar logger
local log = LrLogger('PhotorekaPlugin')
log:enable("logfile")

LrTasks.startAsyncTask(function()
    local catalog = LrApplication.activeCatalog()
    local collection = nil
    
    LrFunctionContext.callWithContext('showPhotorekaCatalog', function(context)
        -- Mostrar un diálogo de progreso si es la primera vez (catálogos grandes)
        local progressScope = LrDialogs.showModalProgressDialog({
            title = 'Loading Photoreka Catalog...',
            caption = 'Synchronizing analyzed photos... (First time may take a while)',
            functionContext = context,
        })
        
        -- Desactivar la colección si ya está activa (para evitar problemas al actualizarla)
        local collectionName = "Photoreka - Analyzed Photos"
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
        
        -- Reconstruir la colección completa con reporte de progreso
        collection = PhotorekaCatalogService.rebuildCollection(function(current, total, caption)
            progressScope:setPortionComplete(current, total)
            progressScope:setCaption(caption)
        end)
        
        progressScope:done()
    end)
    
    -- Activar la colección usando la referencia retornada
    if collection then
        catalog:setActiveSources({ collection })
        log:info("Colección Photoreka activada en el catálogo")
    end
end)
