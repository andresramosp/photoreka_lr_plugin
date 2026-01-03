

local LrHttp = import 'LrHttp'
local LrTasks = import 'LrTasks'

LrTasks.startAsyncTask(function()
    LrHttp.openUrlInBrowser("https://www.photoreka.com/photo-hub#catalog")
end)


-- -- ShowPhotorekaCatalog.lua - Muestra colección de fotos analizadas por Photoreka
-- local LrTasks = import 'LrTasks'
-- local LrDialogs = import 'LrDialogs'
-- local LrFunctionContext = import 'LrFunctionContext'

-- local PhotorekaCatalogService = require 'PhotorekaCatalogService'

-- LrTasks.startAsyncTask(function()
--     LrFunctionContext.callWithContext('showPhotorekaCatalog', function(context)
--         -- Mostrar un diálogo de progreso si es la primera vez (catálogos grandes)
--         local progressScope = LrDialogs.showModalProgressDialog({
--             title = 'Loading Photoreka Catalog...',
--             caption = 'Synchronizing analyzed photos... (First time may take a while)',
--             functionContext = context,
--         })
        
--         -- Reconstruir la colección completa con reporte de progreso
--         PhotorekaCatalogService.rebuildCollection(function(current, total, caption)
--             progressScope:setPortionComplete(current, total)
--             progressScope:setCaption(caption)
--         end)
        
--         progressScope:done()
        
--         -- Activar la colección
--         PhotorekaCatalogService.activateCollection()
--     end)
-- end)
