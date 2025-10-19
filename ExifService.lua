-- ExifService.lua - Servicio de extracción de metadatos EXIF
local LrLogger = import 'LrLogger'

local ExifService = {}

-- Configurar logger
local log = LrLogger('PhotorekaPlugin')
log:enable("logfile")

-- Función para convertir timestamp a formato ISO 8601
local function toISODate(timestamp)
    if timestamp then
        return os.date("!%Y-%m-%dT%H:%M:%S.000Z", timestamp)
    end
    return nil
end

-- Mapeo flexible de campos EXIF (múltiples variantes posibles por campo)
local fieldMapping = {
    -- Para fechas, preferir ISO8601 que ya viene formateado
    dateTimeOriginalISO = {"dateTimeOriginalISO8601", "dateTimeDigitizedISO8601", "dateTimeISO8601"},
    dateTimeOriginalTimestamp = {"dateTimeOriginal", "dateTimeDigitized", "captureTime", "dateTime"},
    iso = {"isoSpeedRating", "isoSpeed", "iso"},
    aperture = {"aperture", "fNumber"},
    shutterSpeed = {"shutterSpeed", "exposureTime"},
    focalLength = {"focalLength"},
    cameraMake = {"cameraMake", "make"},
    cameraModel = {"cameraModel", "model"},
    lens = {"lens", "lensInfo"},
    flash = {"flash"},
    whiteBalance = {"whiteBalance"},
    gps = {"gps"}
}

-- Función para obtener toda la raw metadata de una vez
local function getAllRawMetadata(photo)
    -- NO usar pcall - llamar directamente como en el log que funcionaba
    local rawMetadata = photo:getRawMetadata()
    
    if type(rawMetadata) == "table" then
        local count = 0
        for k, v in pairs(rawMetadata) do
            count = count + 1
        end
        log:info("getAllRawMetadata - tabla con " .. count .. " elementos")
        return rawMetadata
    else
        log:info("getAllRawMetadata - NO es tabla, tipo: " .. type(rawMetadata))
        return {}
    end
end

-- Función para extraer un valor usando múltiples claves posibles (RAW)
-- Ahora trabaja directamente con la tabla de rawMetadata
local function extractRawValue(rawMetadata, possibleKeys, logPrefix)
    for _, key in ipairs(possibleKeys) do
        local value = rawMetadata[key]
        if value ~= nil then
            log:info(logPrefix .. " encontrado en clave '" .. key .. "' = " .. tostring(value))
            return value, key
        end
    end
    
    log:info(logPrefix .. " - no disponible en ninguna variante")
    return nil, nil
end

-- Función para extraer un valor usando múltiples claves posibles (FORMATTED)
local function extractFormattedValue(photo, possibleKeys, logPrefix)
    for _, key in ipairs(possibleKeys) do
        local success, value = pcall(function()
            return photo:getFormattedMetadata(key)
        end)
        
        if success and value ~= nil and value ~= "" then
            log:info(logPrefix .. " encontrado en clave '" .. key .. "' = " .. tostring(value))
            return value, key
        end
    end
    
    log:info(logPrefix .. " - no disponible en ninguna variante")
    return nil, nil
end

-- Extrae los datos EXIF de una foto de Lightroom
-- Parámetro: photo (objeto LrPhoto)
-- Retorna: tabla con estructura de EXIF compatible con la API
-- IMPORTANTE: Esta función DEBE llamarse desde dentro de catalog:withReadAccessDo()
function ExifService.extractExifData(photo)
    log:info("===== EXTRAYENDO EXIF =====")
    
    local exifData = {}
    
    -- Paso 1: Obtener toda la raw metadata de una sola vez
    log:info("=== Obteniendo raw metadata ===")
    local rawMetadata = getAllRawMetadata(photo)
    
    -- Log de todas las keys disponibles
    local keysList = {}
    for key, _ in pairs(rawMetadata) do
        table.insert(keysList, key)
    end
    table.sort(keysList)
    log:info("Claves disponibles en raw metadata (" .. #keysList .. " total):")
    for _, key in ipairs(keysList) do
        local value = rawMetadata[key]
        log:info("  - " .. tostring(key) .. " = " .. tostring(value))
    end
    
    -- Paso 2: Extraer campos usando el mapeo flexible
    log:info("=== Extrayendo campos EXIF ===")
    
    -- Extraer fecha (dateTaken)
    -- Intentar primero con formato ISO8601 que ya viene bien formateado
    local dateTimeOriginalISO = extractRawValue(rawMetadata, fieldMapping.dateTimeOriginalISO, "Fecha ISO")
    if dateTimeOriginalISO then
        -- Ya está en formato ISO, solo necesitamos agregar milisegundos y Z si no los tiene
        if not dateTimeOriginalISO:match("%.%d+Z$") then
            exifData.dateTaken = dateTimeOriginalISO .. ".000Z"
        else
            exifData.dateTaken = dateTimeOriginalISO
        end
    else
        -- Fallback: usar timestamp y convertir
        local dateTimeOriginal = extractRawValue(rawMetadata, fieldMapping.dateTimeOriginalTimestamp, "Fecha timestamp")
        if dateTimeOriginal then
            exifData.dateTaken = toISODate(dateTimeOriginal)
        end
    end
    
    -- Extraer cámara (combinando make y model)
    -- Camera make/model NO están en raw metadata, solo en formatted
    log:info("=== Intentando extraer cámara de formatted metadata ===")
    local cameraMake = extractFormattedValue(photo, fieldMapping.cameraMake, "Fabricante")
    local cameraModel = extractFormattedValue(photo, fieldMapping.cameraModel, "Modelo")
    
    if cameraMake and cameraModel then
        exifData.camera = cameraMake .. " " .. cameraModel
        log:info("Camera completa: " .. exifData.camera)
    elseif cameraModel then
        exifData.camera = cameraModel
        log:info("Solo modelo: " .. exifData.camera)
    elseif cameraMake then
        exifData.camera = cameraMake
        log:info("Solo fabricante: " .. exifData.camera)
    else
        log:info("No se pudo extraer información de cámara")
    end
    
    -- Extraer lens (también solo en formatted)
    log:info("=== Intentando extraer lente de formatted metadata ===")
    local lens = extractFormattedValue(photo, fieldMapping.lens, "Lente")
    if lens then
        exifData.lens = lens
    end
    
    -- Extraer configuraciones técnicas (RAW)
    local focalLength = extractRawValue(rawMetadata, fieldMapping.focalLength, "Distancia focal")
    if focalLength then
        exifData.focalLength = focalLength
    end
    
    local aperture = extractRawValue(rawMetadata, fieldMapping.aperture, "Apertura")
    if aperture then
        exifData.aperture = aperture
    end
    
    local shutterSpeed = extractRawValue(rawMetadata, fieldMapping.shutterSpeed, "Velocidad de obturación")
    if shutterSpeed then
        exifData.exposureTime = shutterSpeed
    end
    
    local iso = extractRawValue(rawMetadata, fieldMapping.iso, "ISO")
    if iso then
        exifData.iso = iso
    end
    
    -- Flash (intentar formatted primero, luego raw)
    log:info("=== Intentando extraer Flash ===")
    local flash = extractFormattedValue(photo, fieldMapping.flash, "Flash (formatted)")
    if not flash then
        flash = extractRawValue(rawMetadata, fieldMapping.flash, "Flash (raw)")
        -- Si es booleano, convertir a texto
        if flash ~= nil then
            if type(flash) == "boolean" then
                flash = flash and "Fired" or "Did not fire"
            end
        end
    end
    if flash then
        exifData.flash = tostring(flash)
    end
    
    -- White Balance (intentar formatted primero, luego raw)
    log:info("=== Intentando extraer White Balance ===")
    local whiteBalance = extractFormattedValue(photo, fieldMapping.whiteBalance, "Balance de blancos (formatted)")
    if not whiteBalance then
        whiteBalance = extractRawValue(rawMetadata, fieldMapping.whiteBalance, "Balance de blancos (raw)")
    end
    if whiteBalance then
        exifData.whiteBalance = tostring(whiteBalance)
    end
    
    -- GPS (puede ser una tabla con latitude, longitude, altitude)
    local gps = extractRawValue(rawMetadata, fieldMapping.gps, "GPS")
    if gps and type(gps) == "table" then
        if gps.latitude and gps.longitude then
            exifData.gpsLatitude = gps.latitude
            exifData.gpsLongitude = gps.longitude
            log:info("GPS coords: lat=" .. tostring(gps.latitude) .. ", lon=" .. tostring(gps.longitude))
            if gps.altitude then
                exifData.gpsAltitude = gps.altitude
                log:info("GPS altitude: " .. tostring(gps.altitude))
            end
        end
    else
        -- Intentar extraer componentes GPS por separado si existen como claves individuales
        local lat = rawMetadata["gpsLatitude"]
        if lat then
            exifData.gpsLatitude = lat
            log:info("GPS Latitud: " .. tostring(lat))
        end
        
        local lon = rawMetadata["gpsLongitude"]
        if lon then
            exifData.gpsLongitude = lon
            log:info("GPS Longitud: " .. tostring(lon))
        end
        
        local alt = rawMetadata["gpsAltitude"]
        if alt then
            exifData.gpsAltitude = alt
            log:info("GPS Altitud: " .. tostring(alt))
        end
    end
    
    -- Contar campos extraídos
    local fieldCount = 0
    for k, v in pairs(exifData) do
        fieldCount = fieldCount + 1
    end
    log:info("===== FIN EXIF (" .. tostring(fieldCount) .. " campos extraídos) =====")
    
    return exifData
end



return ExifService
