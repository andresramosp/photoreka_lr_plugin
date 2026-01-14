-- ExportToPhotoreka.lua
-- Diálogo genérico para exportar fotos seleccionadas a diferentes páginas de Photoreka

local LrFunctionContext = import 'LrFunctionContext'
local LrBinding = import 'LrBinding'
local LrDialogs = import 'LrDialogs'
local LrView = import 'LrView'
local LrTasks = import 'LrTasks'
local LrApplication = import 'LrApplication'
local LrHttp = import 'LrHttp'
local LrLogger = import 'LrLogger'
local Config = require 'Config'

local ApiService = require 'ApiService'

-- Configurar logger
local log = LrLogger('PhotorekaExport')
log:enable("print")

-- Función genérica para exportar fotos a una página específica
local function exportToPage(pagePath, pageName, targetPhotos)
    local catalog = LrApplication.activeCatalog()
    
    log:info("Exporting " .. #targetPhotos .. " photos to " .. pageName)
    
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
        LrDialogs.message("Export to " .. pageName, "Could not extract unique IDs from selected photos.", "warning")
        return
    end
    
    -- Obtener handoff token
    log:info("Obteniendo handoff token...")
    local handoffToken = ApiService.createHandoff()
    
    if not handoffToken then
        LrDialogs.message("Export to " .. pageName, "Could not obtain authentication token. Please try again.", "warning")
        return
    end
    
    -- Construir la URL con los IDs y el handoff token como querystring
    local idsParam = table.concat(uniqueIds, ",")
    local url = Config.APP_BASE_URL .. pagePath .. "?source=lightroom&ids=" .. idsParam .. "&lr_handoff=" .. handoffToken
    
    log:info("Opening URL: " .. url)
    
    -- Abrir la URL en el navegador
    LrHttp.openUrlInBrowser(url)
end

-- Verificar que haya fotos seleccionadas antes de mostrar el diálogo
LrTasks.startAsyncTask(function()
    local catalog = LrApplication.activeCatalog()
    local targetPhotos = catalog:getTargetPhotos()
    
    if #targetPhotos == 0 then
        LrDialogs.message("Export to Photoreka", "Please select at least one photo to export.", "info")
        return
    end
    
    if #targetPhotos > 20 then
        LrDialogs.message("Export to Photoreka", "You can export a maximum of 20 photos at a time. You have selected " .. #targetPhotos .. " photos.", "warning")
        return
    end
    
    log:info("Selected " .. #targetPhotos .. " photos for export")
    
    -- Mostrar diálogo de selección
    LrFunctionContext.callWithContext("exportToPhotoreka", function(context)
        LrDialogs.attachErrorDialogToFunctionContext(context)
        
        local props = LrBinding.makePropertyTable(context)
        props.selectedOption = "canvas"
        
        local f = LrView.osFactory()
        
        local contents = f:column {
            bind_to_object = props,
            spacing = f:control_spacing(),
            fill_horizontal = 1,
            
            f:static_text {
                title = "Select export destination:",
                font = "<system/bold>",
            },
            
            f:radio_button {
                title = "Canvas",
                value = LrView.bind 'selectedOption',
                checked_value = "canvas",
            },
            
            -- f:radio_button {
            --     title = "Series",
            --     value = LrView.bind 'selectedOption',
            --     checked_value = "series",
            -- },
            
            f:radio_button {
                title = "Framer",
                value = LrView.bind 'selectedOption',
                checked_value = "framer",
            },
            
            f:radio_button {
                title = "3D Atlas",
                value = LrView.bind 'selectedOption',
                checked_value = "atlas",
            },
        }
        
        local result = LrDialogs.presentModalDialog {
            title = "Export to Photoreka",
            contents = contents,
            actionVerb = "Export",
        }
        
        if result == "ok" then
            LrTasks.startAsyncTask(function()
                local option = props.selectedOption
                
                if option == "canvas" then
                    exportToPage("/canvas", "Canvas", targetPhotos)
                -- elseif option == "series" then
                --     exportToPage("/series", "Series", targetPhotos)
                elseif option == "framer" then
                    exportToPage("/framer", "Framer", targetPhotos)
                elseif option == "atlas" then
                    if #targetPhotos > 1 then
                        LrDialogs.message("Export to 3D Atlas", "3D Atlas only accepts one photo at a time. You have selected " .. #targetPhotos .. " photos.", "warning")
                    else
                        exportToPage("/atlas", "3D Atlas", targetPhotos)
                    end
                end
            end)
        end
    end)
end)
