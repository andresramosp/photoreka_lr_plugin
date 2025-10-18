-- ApiService.lua - Servicio de comunicación con la API de Photoreka
local LrTasks = import 'LrTasks'

local ApiService = {}

-- Configuración
ApiService.BATCH_SIZE = 5  -- Fotos por lote
ApiService.API_URL = 'https://api.photoreka.com/upload'  -- URL de la API (para implementación futura)

-- Simula el envío de fotos a la API por lotes
-- Parámetros:
--   files: array de rutas de archivos a enviar
--   progressCallback: función que recibe (current, total, caption)
-- Retorna: resultado del envío (true si éxito)
function ApiService.uploadPhotos(files, progressCallback)
    local totalFiles = #files
    local totalBatches = math.ceil(totalFiles / ApiService.BATCH_SIZE)
    local currentBatch = 0
    
    for i = 1, totalFiles, ApiService.BATCH_SIZE do
        currentBatch = currentBatch + 1
        local batchEnd = math.min(i + ApiService.BATCH_SIZE - 1, totalFiles)
        
        if progressCallback then
            progressCallback(
                currentBatch,
                totalBatches,
                string.format(
                    'Enviando lote %d de %d (%d-%d de %d fotos)...',
                    currentBatch,
                    totalBatches,
                    i,
                    batchEnd,
                    totalFiles
                )
            )
        end
        
        -- Simular tiempo de envío a la API (0.5-1.5 segundos por lote)
        -- TODO: Aquí iría la llamada real a la API cuando esté lista
        LrTasks.sleep(0.5 + math.random() * 1.0)
        
        -- Aquí puedes añadir la lógica real de upload:
        -- local response = LrHttp.post(ApiService.API_URL, files[i:batchEnd], headers)
    end
    
    return true
end

-- Función para implementación futura: envío real por HTTP
function ApiService.uploadBatch(filePaths)
    -- TODO: Implementar cuando la API esté lista
    -- local LrHttp = import 'LrHttp'
    -- local response, headers = LrHttp.post(ApiService.API_URL, requestBody, requestHeaders)
    -- return response
    return true
end

return ApiService
