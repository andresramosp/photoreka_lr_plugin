-- SearchMatchService.lua - Servicio de matcheo de fotos entre API y catálogo de Lightroom
local LrLogger = import 'LrLogger'
local LrDate = import 'LrDate'

local Config = require 'Config'

local SearchMatchService = {}

-- Configurar logger
local log = LrLogger('PhotorekaPlugin')
log:enable("logfile")

-- Función auxiliar para obtener el nombre base sin extensión
-- Parámetros:
--   fileName: nombre del archivo con extensión
-- Retorna: nombre sin extensión
local function getBaseName(fileName)
    if not fileName then return nil end
    local lastDot = fileName:match("^(.*)%.")
    return lastDot or fileName
end

-- Función auxiliar para normalizar nombre de archivo
-- Parámetros:
--   fileName: nombre del archivo
-- Retorna: nombre normalizado (minúsculas, sin espacios extras)
local function normalizeFileName(fileName)
    if not fileName then return nil end
    local baseName = getBaseName(fileName)
    if not baseName then return nil end
    return string.lower(baseName):gsub("%s+", " "):gsub("^%s*(.-)%s*$", "%1")
end

-- Función auxiliar para parsear fecha ISO 8601 a timestamp
-- Parámetros:
--   dateString: fecha en formato ISO 8601 (ej: "2025-10-14T03:31:57.000Z")
-- Retorna: timestamp en segundos desde epoch, o nil si falla
local function parseIsoDate(dateString)
    if not dateString then return nil end
    
    -- Pattern para ISO 8601: YYYY-MM-DDTHH:MM:SS(.sss)Z
    local year, month, day, hour, min, sec = dateString:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
    
    if not year then return nil end
    
    -- Convertir a timestamp usando os.time (UTC)
    local timeTable = {
        year = tonumber(year),
        month = tonumber(month),
        day = tonumber(day),
        hour = tonumber(hour),
        min = tonumber(min),
        sec = tonumber(sec)
    }
    
    return os.time(timeTable)
end

-- Función auxiliar para comparar fechas con umbral
-- Parámetros:
--   date1: timestamp 1
--   date2: timestamp 2
--   thresholdHours: umbral en horas (por defecto 24)
-- Retorna: true si las fechas están dentro del umbral
local function datesMatch(date1, date2, thresholdHours)
    thresholdHours = thresholdHours or 24
    
    if not date1 or not date2 then return false end
    
    local diff = math.abs(date1 - date2)
    local thresholdSeconds = thresholdHours * 3600
    
    return diff <= thresholdSeconds
end

-- Función auxiliar para comparar valores EXIF con tolerancia
-- Parámetros:
--   value1: valor 1
--   value2: valor 2
--   tolerance: tolerancia para números (porcentaje, 0-1)
-- Retorna: true si los valores coinciden
local function exifValuesMatch(value1, value2, tolerance)
    tolerance = tolerance or 0.01  -- 1% por defecto
    
    if value1 == nil or value2 == nil then return false end
    
    -- Si son del mismo tipo y coinciden exactamente
    if value1 == value2 then return true end
    
    -- Si son números, comparar con tolerancia
    local num1 = tonumber(value1)
    local num2 = tonumber(value2)
    
    if num1 and num2 then
        if num1 == 0 and num2 == 0 then return true end
        if num1 == 0 or num2 == 0 then return false end
        
        local diff = math.abs(num1 - num2)
        local avg = (num1 + num2) / 2
        
        return (diff / avg) <= tolerance
    end
    
    -- Si son strings, comparar case-insensitive
    local str1 = tostring(value1):lower()
    local str2 = tostring(value2):lower()
    
    return str1 == str2
end

-- Calcula un score de similitud EXIF entre dos conjuntos de datos
-- Parámetros:
--   apiExif: datos EXIF de la API
--   lrExif: datos EXIF de Lightroom
-- Retorna: score entre 0 y 1 (1 = coincidencia perfecta)
local function calculateExifSimilarity(apiExif, lrExif)
    if not apiExif or not lrExif then return 0 end
    
    local matches = 0
    local total = 0
    
    -- Comparar cámara (make + model)
    if apiExif.camera and lrExif.cameraMake then
        total = total + 1
        if exifValuesMatch(apiExif.camera.make, lrExif.cameraMake) then
            matches = matches + 1
        end
    end
    
    if apiExif.camera and lrExif.cameraModel then
        total = total + 1
        if exifValuesMatch(apiExif.camera.model, lrExif.cameraModel) then
            matches = matches + 1
        end
    end
    
    -- Comparar lente
    if apiExif.camera and apiExif.camera.lens and lrExif.lens then
        total = total + 1
        if exifValuesMatch(apiExif.camera.lens, lrExif.lens) then
            matches = matches + 1
        end
    end
    
    -- Comparar settings (ISO, aperture, focal length, exposure time)
    if apiExif.settings and lrExif.iso then
        total = total + 1
        if exifValuesMatch(apiExif.settings.iso, lrExif.iso, 0.01) then
            matches = matches + 1
        end
    end
    
    if apiExif.settings and lrExif.aperture then
        total = total + 1
        if exifValuesMatch(apiExif.settings.aperture, lrExif.aperture, 0.05) then  -- 5% tolerancia
            matches = matches + 1
        end
    end
    
    if apiExif.settings and lrExif.focalLength then
        total = total + 1
        if exifValuesMatch(apiExif.settings.focalLength, lrExif.focalLength, 0.05) then
            matches = matches + 1
        end
    end
    
    if apiExif.settings and lrExif.shutterSpeed then
        total = total + 1
        if exifValuesMatch(apiExif.settings.exposureTime, lrExif.shutterSpeed, 0.05) then
            matches = matches + 1
        end
    end
    
    -- Si no hay datos para comparar, retornar 0
    if total == 0 then return 0 end
    
    return matches / total
end

-- Extrae datos EXIF de una foto de Lightroom
-- Parámetros:
--   photo: foto de Lightroom
-- Retorna: tabla con datos EXIF extraídos
local function extractLightroomExif(photo)
    local exif = {}
    
    -- Usar pcall para evitar errores si algún campo no está disponible
    local function safeGet(fieldName)
        local success, value = pcall(function()
            return photo:getFormattedMetadata(fieldName)
        end)
        return success and value or nil
    end
    
    exif.cameraMake = safeGet('cameraMake')
    exif.cameraModel = safeGet('cameraModel')
    exif.lens = safeGet('lens')
    exif.iso = safeGet('isoSpeedRating')
    exif.aperture = safeGet('aperture')
    exif.focalLength = safeGet('focalLength')
    exif.shutterSpeed = safeGet('shutterSpeed')
    exif.dateTimeOriginal = safeGet('dateTimeOriginal')
    
    return exif
end

-- Extrae datos EXIF de una foto de la API
-- Parámetros:
--   apiPhoto: tabla con datos de la foto de la API
-- Retorna: tabla con datos EXIF normalizados
local function extractApiExif(apiPhoto)
    if not apiPhoto or not apiPhoto.descriptions or not apiPhoto.descriptions.EXIF then
        return nil
    end
    
    return apiPhoto.descriptions.EXIF
end

-- Busca fotos en Lightroom por uniqueId
-- Parámetros:
--   catalog: catálogo de Lightroom
--   uniqueId: uniqueId a buscar
--   allPhotos: array de todas las fotos del catálogo (opcional, para optimización)
-- Retorna: foto encontrada o nil
local function findPhotoByUniqueId(catalog, uniqueId, allPhotos)
    if not uniqueId then return nil end
    
    local uniqueIdStr = tostring(uniqueId)
    
    -- Si no se proporcionó allPhotos, obtenerlas
    if not allPhotos then
        allPhotos = catalog:getAllPhotos()
    end
    
    for _, photo in ipairs(allPhotos) do
        if photo and photo.localIdentifier then
            if tostring(photo.localIdentifier) == uniqueIdStr then
                return photo
            end
        end
    end
    
    return nil
end

-- Busca fotos en Lightroom por nombre de archivo y fecha
-- Parámetros:
--   catalog: catálogo de Lightroom
--   fileName: nombre del archivo (sin extensión)
--   dateTaken: fecha de captura en formato ISO 8601
--   allPhotos: array de todas las fotos del catálogo (opcional)
-- Retorna: array de fotos candidatas con su score
local function findPhotosByFileNameAndDate(catalog, fileName, dateTaken, allPhotos)
    if not fileName then return {} end
    
    local normalizedFileName = normalizeFileName(fileName)
    if not normalizedFileName then return {} end
    
    local apiDateTimestamp = parseIsoDate(dateTaken)
    
    -- Si no se proporcionó allPhotos, obtenerlas
    if not allPhotos then
        allPhotos = catalog:getAllPhotos()
    end
    
    local candidates = {}
    
    for _, photo in ipairs(allPhotos) do
        if photo then
            -- Obtener nombre de archivo de la foto
            local success, lrFileName = pcall(function()
                return photo:getFormattedMetadata('fileName')
            end)
            
            if success and lrFileName then
                local normalizedLrFileName = normalizeFileName(lrFileName)
                
                -- Verificar coincidencia de nombre
                if normalizedLrFileName == normalizedFileName then
                    -- Calcular score basado en fecha
                    local dateScore = 0
                    
                    if apiDateTimestamp then
                        local lrDateSuccess, lrDateString = pcall(function()
                            return photo:getFormattedMetadata('dateTimeOriginal')
                        end)
                        
                        if lrDateSuccess and lrDateString then
                            -- Convertir fecha de Lightroom a timestamp
                            -- Formato esperado puede variar, intentar parsear
                            local lrTimestamp = LrDate.timeFromIsoDate(lrDateString)
                            
                            if lrTimestamp then
                                -- Calcular diferencia en horas
                                local diffHours = math.abs(apiDateTimestamp - lrTimestamp) / 3600
                                
                                -- Score inversamente proporcional a la diferencia
                                -- 0 horas = 1.0, 24 horas = 0.0
                                if diffHours <= 24 then
                                    dateScore = 1 - (diffHours / 24)
                                end
                            end
                        end
                    end
                    
                    table.insert(candidates, {
                        photo = photo,
                        dateScore = dateScore
                    })
                end
            end
        end
    end
    
    return candidates
end

-- Busca fotos en Lightroom usando matcheo EXIF avanzado
-- Parámetros:
--   catalog: catálogo de Lightroom
--   fileName: nombre del archivo (sin extensión)
--   apiExif: datos EXIF de la API
--   allPhotos: array de todas las fotos del catálogo (opcional)
-- Retorna: array de fotos candidatas con su score EXIF
local function findPhotosByExif(catalog, fileName, apiExif, allPhotos)
    if not fileName or not apiExif then return {} end
    
    local normalizedFileName = normalizeFileName(fileName)
    if not normalizedFileName then return {} end
    
    -- Si no se proporcionó allPhotos, obtenerlas
    if not allPhotos then
        allPhotos = catalog:getAllPhotos()
    end
    
    local candidates = {}
    
    for _, photo in ipairs(allPhotos) do
        if photo then
            -- Obtener nombre de archivo de la foto
            local success, lrFileName = pcall(function()
                return photo:getFormattedMetadata('fileName')
            end)
            
            if success and lrFileName then
                local normalizedLrFileName = normalizeFileName(lrFileName)
                
                -- Verificar coincidencia de nombre
                if normalizedLrFileName == normalizedFileName then
                    -- Extraer EXIF de Lightroom
                    local lrExif = extractLightroomExif(photo)
                    
                    -- Calcular similitud EXIF
                    local exifScore = calculateExifSimilarity(apiExif, lrExif)
                    
                    if exifScore > 0 then
                        table.insert(candidates, {
                            photo = photo,
                            exifScore = exifScore
                        })
                    end
                end
            end
        end
    end
    
    return candidates
end

-- FUNCIÓN PRINCIPAL: Busca fotos en Lightroom usando estrategia multi-nivel
-- Parámetros:
--   catalog: catálogo de Lightroom
--   searchData: array de tablas {uniqueId, fileName, apiPhoto}
-- Retorna: array de fotos encontradas
function SearchMatchService.findPhotos(catalog, searchData)
    local foundPhotos = {}
    local foundSet = {}  -- Para evitar duplicados
    
    log:info("========================================")
    log:info("INICIANDO BÚSQUEDA DE FOTOS CON MATCHEO MULTI-NIVEL")
    log:info("Total fotos a buscar: " .. tostring(#searchData))
    log:info("========================================")
    
    -- Obtener todas las fotos del catálogo UNA VEZ para optimización
    local allPhotos = catalog:getAllPhotos()
    log:info("Catálogo contiene " .. tostring(#allPhotos) .. " fotos totales")
    
    -- Contadores de estrategias
    local stats = {
        byUniqueId = 0,
        byFileNameAndDate = 0,
        byExif = 0,
        notFound = 0
    }
    
    -- Procesar cada foto
    for i, data in ipairs(searchData) do
        local photo = nil
        local matchStrategy = nil
        local shouldTryFallback = Config.USE_SEARCH_FALLBACK
        
        -- ESTRATEGIA 1: Buscar por uniqueId (más confiable)
        if data.uniqueId then
            photo = findPhotoByUniqueId(catalog, data.uniqueId, allPhotos)
            if photo then
                matchStrategy = "uniqueId"
                log:info(string.format("[%d] ✓ Encontrada por uniqueId: %s", i, tostring(data.uniqueId)))
            end
        end
        
        -- ESTRATEGIA 2: Buscar por nombre de archivo + fecha (fallback)
        if not photo and shouldTryFallback and data.fileName and data.apiPhoto then
            local apiExif = extractApiExif(data.apiPhoto)
            local dateTaken = apiExif and apiExif.dateTaken
            
            if dateTaken then
                local candidates = findPhotosByFileNameAndDate(catalog, data.fileName, dateTaken, allPhotos)
                
                if #candidates > 0 then
                    -- Ordenar por dateScore descendente
                    table.sort(candidates, function(a, b)
                        return a.dateScore > b.dateScore
                    end)
                    
                    local bestCandidate = candidates[1]
                    
                    -- Aceptar si dateScore > 0.5 (menos de 12 horas de diferencia)
                    if bestCandidate.dateScore > 0.5 then
                        photo = bestCandidate.photo
                        matchStrategy = "fileNameAndDate"
                        log:info(string.format("[%d] ✓ Encontrada por fileName+fecha: %s (score: %.2f)", 
                            i, data.fileName, bestCandidate.dateScore))
                        
                        if #candidates > 1 then
                            log:info(string.format("     (Había %d candidatos, elegido el mejor)", #candidates))
                        end
                    else
                        log:info(string.format("[%d] ⚠ Candidatos encontrados por fileName pero dateScore muy bajo: %.2f", 
                            i, bestCandidate.dateScore))
                    end
                end
            end
        end
        
        -- ESTRATEGIA 3: Buscar por EXIF avanzado (último recurso)
        if not photo and shouldTryFallback and data.fileName and data.apiPhoto then
            local apiExif = extractApiExif(data.apiPhoto)
            
            if apiExif then
                local candidates = findPhotosByExif(catalog, data.fileName, apiExif, allPhotos)
                
                if #candidates > 0 then
                    -- Ordenar por exifScore descendente
                    table.sort(candidates, function(a, b)
                        return a.exifScore > b.exifScore
                    end)
                    
                    local bestCandidate = candidates[1]
                    
                    -- Aceptar si exifScore > 0.7 (70% de coincidencia EXIF)
                    if bestCandidate.exifScore > 0.7 then
                        photo = bestCandidate.photo
                        matchStrategy = "exif"
                        log:info(string.format("[%d] ✓ Encontrada por EXIF: %s (score: %.2f)", 
                            i, data.fileName, bestCandidate.exifScore))
                        
                        if #candidates > 1 then
                            log:info(string.format("     (Había %d candidatos, elegido el mejor)", #candidates))
                        end
                    else
                        log:info(string.format("[%d] ⚠ Candidatos encontrados por fileName pero exifScore muy bajo: %.2f", 
                            i, bestCandidate.exifScore))
                    end
                end
            end
        end
        
        -- Añadir a resultados si se encontró y no es duplicado
        if photo then
            local photoKey = tostring(photo.localIdentifier)
            
            if not foundSet[photoKey] then
                table.insert(foundPhotos, photo)
                foundSet[photoKey] = true
                
                -- Actualizar estadísticas
                if matchStrategy == "uniqueId" then
                    stats.byUniqueId = stats.byUniqueId + 1
                elseif matchStrategy == "fileNameAndDate" then
                    stats.byFileNameAndDate = stats.byFileNameAndDate + 1
                elseif matchStrategy == "exif" then
                    stats.byExif = stats.byExif + 1
                end
            else
                log:info(string.format("[%d] ✗ No se pudo encontrar: fileName=%s, uniqueId=%s", 
                    i, tostring(data.fileName), tostring(data.uniqueId)))
            end
        else
            -- No se encontró y no hay más estrategias disponibles
            stats.notFound = stats.notFound + 1
            if not shouldTryFallback then
                log:info(string.format("[%d] ✗ No hay uniqueId y fallback deshabilitado - fileName=%s", 
                    i, tostring(data.fileName)))
            else
                log:info(string.format("[%d] ✗ No se pudo encontrar: fileName=%s, uniqueId=%s", 
                    i, tostring(data.fileName), tostring(data.uniqueId)))
            end
        end
    end
    
    -- Resumen de estadísticas
    log:info("========================================")
    log:info("RESUMEN DE BÚSQUEDA:")
    log:info(string.format("  - Por uniqueId: %d", stats.byUniqueId))
    log:info(string.format("  - Por fileName+fecha: %d", stats.byFileNameAndDate))
    log:info(string.format("  - Por EXIF: %d", stats.byExif))
    log:info(string.format("  - No encontradas: %d", stats.notFound))
    log:info(string.format("  - TOTAL ENCONTRADAS: %d de %d", #foundPhotos, #searchData))
    log:info("========================================")
    
    return foundPhotos
end

return SearchMatchService
