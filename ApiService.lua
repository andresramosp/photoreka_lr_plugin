-- ApiService.lua - Servicio de comunicación con la API de Photoreka
local LrTasks = import 'LrTasks'

local ApiService = {}

-- Configuración
ApiService.BATCH_SIZE = 5  -- Fotos por lote
ApiService.API_URL = 'https://api.photoreka.com/upload'  -- URL de la API (para implementación futura)

-- Simula el envío de fotos a la API por lotes
-- Parámetros:
--   photoData: tabla con {fullPhotos = {...}, thumbPhotos = {...}}
--   progressCallback: función que recibe (current, total, caption)
-- Retorna: resultado del envío (true si éxito)
function ApiService.uploadPhotos(photoData, progressCallback)
    local fullPhotos = photoData.fullPhotos or {}
    local thumbPhotos = photoData.thumbPhotos or {}
    local totalPhotos = #fullPhotos
    local totalBatches = math.ceil(totalPhotos / ApiService.BATCH_SIZE)
    local currentBatch = 0
    
    for i = 1, totalPhotos, ApiService.BATCH_SIZE do
        currentBatch = currentBatch + 1
        local batchEnd = math.min(i + ApiService.BATCH_SIZE - 1, totalPhotos)
        
        -- Preparar lote con ambas versiones
        local batchData = {
            full = {},
            thumbs = {}
        }
        
        for j = i, batchEnd do
            table.insert(batchData.full, fullPhotos[j])
            table.insert(batchData.thumbs, thumbPhotos[j])
        end
        
        if progressCallback then
            progressCallback(
                currentBatch,
                totalBatches,
                string.format(
                    'Enviando lote %d de %d (%d-%d de %d fotos con thumbs)...',
                    currentBatch,
                    totalBatches,
                    i,
                    batchEnd,
                    totalPhotos
                )
            )
        end
        
        -- Simular tiempo de envío a la API (0.5-1.5 segundos por lote)
        -- TODO: Aquí iría la llamada real a la API cuando esté lista
        -- Cada lote incluye las fotos full y thumbs correspondientes
        LrTasks.sleep(0.5 + math.random() * 1.0)
        
        -- Aquí puedes añadir la lógica real de upload:
        -- local response = ApiService.uploadBatch(batchData)
    end
    
    return true
end

-- Función para implementación futura: envío real por HTTP
-- Parámetros:
--   batchData: tabla con {full = {...}, thumbs = {...}}
function ApiService.uploadBatch(batchData)
    -- TODO: Implementar cuando la API esté lista
    -- local LrHttp = import 'LrHttp'
    -- El request debe incluir tanto las fotos full como los thumbnails
    -- local requestBody = {
    --     fullPhotos = batchData.full,
    --     thumbnails = batchData.thumbs
    -- }
    -- local response, headers = LrHttp.post(ApiService.API_URL, requestBody, requestHeaders)
    -- return response
    return true
end

return ApiService
