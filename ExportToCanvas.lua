-- ExportToCanvas.lua
-- Abre Canvas de Photoreka en el navegador web con las fotos seleccionadas

local LrHttp = import 'LrHttp'
local LrTasks = import 'LrTasks'
local LrApplication = import 'LrApplication'
local LrDialogs = import 'LrDialogs'
local LrLogger = import 'LrLogger'

-- Configurar logger
local log = LrLogger('PhotorekaExportToCanvas')
log:enable("print")

LrTasks.startAsyncTask(function()
    local catalog = LrApplication.activeCatalog()
    local targetPhotos = catalog:getTargetPhotos()
    
    if #targetPhotos == 0 then
        LrDialogs.message("Export to Canvas", "Please select at least one photo to export to Canvas.", "info")
        return
    end
    
    log:info("Exporting " .. #targetPhotos .. " photos to Canvas")
    
    -- Extraer uniqueIds de las fotos seleccionadas
    local uniqueIds = {}
    catalog:withReadAccessDo(function()
        for i, photo in ipairs(targetPhotos) do
            local uniqueId = photo.localIdentifier or photo:getRawMetadata('uuid')
            if uniqueId then
                table.insert(uniqueIds, uniqueId)
                log:info("Photo " .. i .. " uniqueId: " .. uniqueId)
            else
                log:warn("Photo " .. i .. " has no uniqueId")
            end
        end
    end)
    
    if #uniqueIds == 0 then
        LrDialogs.message("Export to Canvas", "Could not extract unique IDs from selected photos.", "warning")
        return
    end
    
    -- Construir la URL con los IDs como querystring
    local idsParam = table.concat(uniqueIds, ",")
    local url = "https://www.photoreka.com/canvas?source=lightroom&ids=" .. idsParam
    
    log:info("Opening URL: " .. url)
    
    -- Abrir la URL en el navegador
    LrHttp.openUrlInBrowser(url)
end)
