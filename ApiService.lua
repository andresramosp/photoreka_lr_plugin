-- ApiService.lua - Servicio de comunicación con la API de Photoreka
local LrTasks = import 'LrTasks'
local LrHttp = import 'LrHttp'
local LrFileUtils = import 'LrFileUtils'
local LrPathUtils = import 'LrPathUtils'
local LrDialogs = import 'LrDialogs'
local LrLogger = import 'LrLogger'

local JSON = require 'JSON'

local ApiService = {}

-- Configurar logger
local log = LrLogger('PhotorekaPlugin')
log:enable("logfile")

-- ========================================
-- CONFIGURACIÓN - EDITAR ESTAS VARIABLES
-- ========================================
ApiService.API_BASE_URL = 'http://localhost:3333'
ApiService.ANALYZER_API_BASE_URL = 'http://localhost:3333'
ApiService.AUTH_TOKEN = 'oat_NDQ.MG5INjlLNldpMExiLVRITGE4TG9kUXZvd1ZpM0t6ZUxvYThtNUtKdzE5MDMyOTE4MTY'  -- SETEAR TOKEN AQUÍ PARA PRUEBAS (sin "Bearer ")
ApiService.USE_MOCK_EXIF = true  -- true = usar EXIF inventados, false = extraer EXIF reales
-- ========================================

-- Configuración de comportamiento
ApiService.MAX_RETRIES = 3  -- Reintentos por subida
ApiService.CONCURRENT_UPLOADS = 5  -- Número de subidas simultáneas (similar a p-limit)

log:info("ApiService cargado. API_BASE_URL: " .. ApiService.API_BASE_URL)

-- Valida que el token esté configurado
local function validateToken()
    if not ApiService.AUTH_TOKEN or ApiService.AUTH_TOKEN == '' then
        error("AUTH_TOKEN no está configurado. Por favor, edita ApiService.lua y setea ApiService.AUTH_TOKEN")
    end
end

-- Lee un archivo como datos binarios
-- Parámetros:
--   filePath: ruta absoluta al archivo
-- Retorna: contenido del archivo como string binario
local function readFileAsBinary(filePath)
    local file = io.open(filePath, "rb")
    if not file then
        error("No se pudo abrir el archivo: " .. filePath)
    end
    local fileData = file:read("*all")
    file:close()
    return fileData
end

-- Obtiene el nombre del archivo de una ruta
-- Parámetros:
--   filePath: ruta completa del archivo
-- Retorna: nombre del archivo
local function getFileName(filePath)
    return LrPathUtils.leafName(filePath)
end

-- Sube un archivo a Cloudflare R2 con reintentos
-- Parámetros:
--   url: URL firmada de R2
--   filePath: ruta del archivo a subir
--   fileType: tipo MIME (ej: "image/jpeg")
--   maxRetries: número máximo de reintentos
-- Retorna: true si éxito, error si falla
local function uploadToR2WithRetry(url, filePath, fileType, maxRetries)
    maxRetries = maxRetries or ApiService.MAX_RETRIES
    
    -- Leer el archivo una sola vez
    log:info("Leyendo archivo: " .. tostring(filePath))
    local fileData = readFileAsBinary(filePath)
    local fileName = getFileName(filePath)
    log:info("Archivo leído, tamaño: " .. tostring(string.len(fileData)) .. " bytes")
    
    for attempt = 1, maxRetries do
        log:info(string.format("Intento %d de %d para subir %s", attempt, maxRetries, fileName))
        
        -- Preparar headers
        local headers = {
            { field = "Content-Type", value = fileType }
        }
        
        -- Hacer PUT request
        log:info("Haciendo PUT a R2...")
        local response, responseHeaders = LrHttp.post(url, fileData, headers, "PUT")
        
        if response and responseHeaders then
            -- Verificar código de estado
            local statusCode = tonumber(responseHeaders.status)
            log:info("R2 Response status: " .. tostring(statusCode))
            
            if statusCode and statusCode >= 200 and statusCode < 300 then
                log:info("Upload exitoso!")
                return true  -- Éxito
            else
                log:error(string.format("R2 error %d: %s", statusCode or 0, tostring(response)))
            end
        else
            log:error("No response from R2")
        end
        
        -- Si no fue exitoso y no es el último intento, esperar con backoff exponencial
        if attempt < maxRetries then
            local delay = math.pow(2, attempt)  -- 2s, 4s, 8s
            log:info("Esperando " .. tostring(delay) .. " segundos antes de reintentar...")
            LrTasks.sleep(delay)
        end
    end
    
    log:error(string.format("Failed to upload %s after %d attempts", fileName, maxRetries))
    error(string.format("Failed to upload %s after %d attempts", fileName, maxRetries))
end

-- Solicita URLs firmadas al backend para una foto
-- Parámetros:
--   originalName: nombre original del archivo
--   exifData: tabla con metadatos EXIF
--   sourceData: tabla con información de origen {type, uniqueId}
-- Retorna: tabla con {uploadUrl, thumbnailUploadUrl, photo}
local function requestUploadUrls(originalName, exifData, sourceData)
    validateToken()
    
    local url = ApiService.API_BASE_URL .. "/api/catalog/uploadPhoto"
    
    local payload = {
        fileType = "image/jpeg",
        originalName = originalName,
        source = sourceData,
        exifData = exifData
    }
    
    log:info("Preparando request a: " .. url)
    
    local headers = {
        { field = "Authorization", value = "Bearer " .. ApiService.AUTH_TOKEN },
        { field = "Content-Type", value = "application/json" }
    }
    
    local body = JSON.encode(payload)
    log:info("Body JSON length: " .. tostring(string.len(body)))
    
    local response, responseHeaders = LrHttp.post(url, body, headers)
    
    if not response then
        log:error("ERROR: No response from server")
        error("Failed to get upload URLs from server")
    end
    
    log:info("Response recibida, length: " .. tostring(string.len(response)))
    
    -- Verificar código de estado
    if responseHeaders and responseHeaders.status then
        local statusCode = tonumber(responseHeaders.status)
        log:info("Status code: " .. tostring(statusCode))
        
        if statusCode and (statusCode < 200 or statusCode >= 300) then
            log:error("Server error " .. tostring(statusCode) .. ": " .. tostring(response))
            error(string.format("Server returned error %d: %s", statusCode, response or "unknown error"))
        end
    end
    
    log:info("Decodificando JSON response...")
    local responseData = JSON.decode(response)
    log:info("JSON decodificado OK")
    
    return responseData
end

-- Procesa y sube una foto individual (main + thumbnail)
-- Parámetros:
--   mainImagePath: ruta al archivo principal (1500px)
--   thumbnailPath: ruta al thumbnail (800px)
--   exifData: metadatos EXIF
--   sourceData: tabla con información de origen {type, uniqueId}
-- Retorna: tabla con información de la foto subida
local function processAndUploadPhoto(mainImagePath, thumbnailPath, exifData, sourceData)
    local originalName = getFileName(mainImagePath)
    
    -- LOG: Inicio del proceso
    log:info("===== PROCESANDO FOTO =====")
    log:info("Nombre: " .. tostring(originalName))
    log:info("Path main: " .. tostring(mainImagePath))
    log:info("Path thumb: " .. tostring(thumbnailPath))
    
    -- 1. Solicitar URLs firmadas
    log:info("PASO 1: Solicitando URLs firmadas...")
    local uploadData = requestUploadUrls(originalName, exifData, sourceData)
    
    log:info("URLs recibidas OK")
    log:info("Upload URL: " .. tostring(uploadData.uploadUrl))
    log:info("Thumb URL: " .. tostring(uploadData.thumbnailUploadUrl))
    
    if not uploadData.uploadUrl or not uploadData.thumbnailUploadUrl then
        log:error("ERROR: Server did not return upload URLs")
        error("Server did not return upload URLs")
    end
    
    -- 2. Subir archivo principal a R2
    log:info("PASO 2: Subiendo imagen principal...")
    uploadToR2WithRetry(
        uploadData.uploadUrl,
        mainImagePath,
        "image/jpeg",
        ApiService.MAX_RETRIES
    )
    
    log:info("Imagen principal subida OK")
    
    -- 3. Subir thumbnail a R2
    log:info("PASO 3: Subiendo thumbnail...")
    uploadToR2WithRetry(
        uploadData.thumbnailUploadUrl,
        thumbnailPath,
        "image/jpeg",
        ApiService.MAX_RETRIES
    )
    
    log:info("Thumbnail subido OK")
    log:info("===== FOTO COMPLETADA =====")
    
    return uploadData.photo
end

-- Trigger de post-procesamiento en el backend
-- Se debe llamar UNA VEZ después de subir todas las fotos
-- Parámetros:
--   photoIds: array de IDs de fotos subidas exitosamente
local function triggerProcess(photoIds)
    validateToken()
    
    local url = ApiService.ANALYZER_API_BASE_URL .. "/api/analyzer"
    
    local payload = {
        packageId = "process",
        mode = "adding",
        photoIds = photoIds
    }
    
    local headers = {
        { field = "Authorization", value = "Bearer " .. ApiService.AUTH_TOKEN },
        { field = "Content-Type", value = "application/json" }
    }
    
    local body = JSON.encode(payload)
    local response, responseHeaders = LrHttp.post(url, body, headers)
    
    if not response then
        error("Failed to trigger preprocessing")
    end
    
    return true
end

-- Procesa fotos con límite de concurrencia (similar a p-limit)
-- Parámetros:
--   tasks: array de funciones que retornan el resultado de procesar cada foto
--   limit: número máximo de tareas simultáneas
--   progressCallback: función de progreso
--   totalPhotos: total de fotos para el callback
-- Retorna: array de resultados {success = true/false, result = data/error}
local function processWithConcurrencyLimit(tasks, limit, progressCallback, totalPhotos)
    local results = {}
    local completed = 0
    local activeTasks = {}
    local nextTaskIndex = 1
    local totalTasks = #tasks
    
    log:info(string.format("Iniciando procesamiento concurrente: %d tareas, límite: %d", totalTasks, limit))
    
    -- Función para iniciar una nueva tarea
    local function startNextTask()
        if nextTaskIndex > totalTasks then
            return false -- No hay más tareas
        end
        
        local taskIndex = nextTaskIndex
        nextTaskIndex = nextTaskIndex + 1
        
        log:info(string.format("Iniciando tarea %d de %d", taskIndex, totalTasks))
        
        -- Crear y lanzar la tarea asíncrona
        local task = LrTasks.startAsyncTask(function()
            local success, result = LrTasks.pcall(tasks[taskIndex])
            
            -- Guardar resultado
            results[taskIndex] = {
                success = success,
                result = result
            }
            
            completed = completed + 1
            
            if progressCallback then
                progressCallback(
                    completed,
                    totalPhotos,
                    string.format('Subiendo foto %d de %d...', completed, totalPhotos)
                )
            end
            
            log:info(string.format("Tarea %d completada (%d/%d)", taskIndex, completed, totalTasks))
            
            -- Marcar esta tarea como completada
            for i, t in ipairs(activeTasks) do
                if t.index == taskIndex then
                    table.remove(activeTasks, i)
                    break
                end
            end
            
            -- Iniciar la siguiente tarea si hay espacio
            if #activeTasks < limit then
                startNextTask()
            end
        end)
        
        table.insert(activeTasks, {index = taskIndex, task = task})
        return true
    end
    
    -- Iniciar las primeras N tareas (hasta el límite)
    for i = 1, math.min(limit, totalTasks) do
        startNextTask()
    end
    
    -- Esperar a que todas las tareas se completen
    while completed < totalTasks do
        LrTasks.sleep(0.1) -- Pequeña pausa para no saturar CPU
    end
    
    log:info(string.format("Procesamiento concurrente completado: %d/%d tareas", completed, totalTasks))
    
    return results
end

-- FUNCIÓN PRINCIPAL: Sube fotos a la API de Photoreka
-- Parámetros:
--   photoData: tabla con {fullPhotos = {...}, thumbPhotos = {...}, exifDataList = {...}, sourceDataList = {...}}
--   progressCallback: función que recibe (current, total, caption)
-- Retorna: tabla con {successfulUploads = {...}, failedUploads = {...}}
function ApiService.uploadPhotos(photoData, progressCallback)
    local fullPhotos = photoData.fullPhotos or {}
    local thumbPhotos = photoData.thumbPhotos or {}
    local exifDataList = photoData.exifDataList or {}
    local sourceDataList = photoData.sourceDataList or {}
    local totalPhotos = #fullPhotos
    
    log:info("========================================")
    log:info("INICIANDO SUBIDA DE FOTOS CON CONCURRENCIA")
    log:info("Total fotos: " .. tostring(totalPhotos))
    log:info("Full photos: " .. tostring(#fullPhotos))
    log:info("Thumb photos: " .. tostring(#thumbPhotos))
    log:info("EXIF data: " .. tostring(#exifDataList))
    log:info("Concurrent uploads: " .. tostring(ApiService.CONCURRENT_UPLOADS))
    log:info("========================================")
    
    -- Validar que los arrays tengan la misma longitud
    if #thumbPhotos ~= totalPhotos then
        log:error("ERROR: Mismatch en cantidad de fotos!")
        error("Mismatch: fullPhotos and thumbPhotos must have the same length")
    end
    
    local successfulUploads = {}
    local failedUploads = {}
    
    -- Crear array de tareas (una por foto)
    local tasks = {}
    for i = 1, totalPhotos do
        tasks[i] = function()
            log:info("")
            log:info("========================================")
            log:info(string.format("PROCESANDO FOTO %d de %d", i, totalPhotos))
            log:info("========================================")
            
            -- Preparar datos
            local exifData = exifDataList[i]
            if not exifData then
                log:warn("No EXIF data para foto " .. tostring(i) .. ", usando mock")
                local ExifService = require 'ExifService'
                exifData = ExifService.getMockExifData()
            end
            
            local sourceData = sourceDataList[i]
            if not sourceData then
                log:warn("No source data para foto " .. tostring(i) .. ", usando default")
                sourceData = { type = "lightroom", uniqueId = nil }
            end
            
            -- Procesar y subir foto
            return processAndUploadPhoto(
                fullPhotos[i],
                thumbPhotos[i],
                exifData,
                sourceData
            )
        end
    end
    
    -- Procesar fotos con límite de concurrencia
    local results = processWithConcurrencyLimit(
        tasks,
        ApiService.CONCURRENT_UPLOADS,
        progressCallback,
        totalPhotos
    )
    
    -- Procesar resultados
    for i, result in ipairs(results) do
        if result.success then
            log:info("✓ Foto " .. tostring(i) .. " subida exitosamente")
            table.insert(successfulUploads, result.result)
        else
            log:error("✗ Foto " .. tostring(i) .. " FALLÓ: " .. tostring(result.result))
            table.insert(failedUploads, {
                mainPath = fullPhotos[i],
                thumbPath = thumbPhotos[i],
                error = tostring(result.result)
            })
        end
    end
    
    log:info("")
    log:info("========================================")
    log:info("RESUMEN DE SUBIDA")
    log:info("Exitosas: " .. tostring(#successfulUploads))
    log:info("Fallidas: " .. tostring(#failedUploads))
    log:info("========================================")
    
    -- Si hubo éxitos, trigger preprocessing
    if #successfulUploads > 0 then
        log:info("Triggering preprocessing...")
        
        -- Extraer IDs de las fotos subidas exitosamente
        local photoIds = {}
        for _, photo in ipairs(successfulUploads) do
            if photo.id then
                table.insert(photoIds, photo.id)
            end
        end
        
        log:info("Photo IDs para preprocessing: " .. JSON.encode(photoIds))
        
        local success, result = LrTasks.pcall(function()
            return triggerProcess(photoIds)
        end)
        if not success then
            -- Log error pero no fallar el proceso completo
            log:error("Warning: Failed to trigger preprocessing - " .. tostring(result))
            print("Warning: Failed to trigger preprocessing - " .. tostring(result))
        else
            log:info("Preprocessing triggered OK")
        end
    end
    
    return {
        successfulUploads = successfulUploads,
        failedUploads = failedUploads
    }
end

return ApiService
