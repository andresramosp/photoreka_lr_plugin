-- ExifService.lua - Servicio de extracción de metadatos EXIF
local ExifService = {}

-- Función para convertir timestamp a formato ISO 8601
local function toISODate(timestamp)
    if timestamp then
        return os.date("!%Y-%m-%dT%H:%M:%S.000Z", timestamp)
    end
    return nil
end

-- Extrae los datos EXIF de una foto de Lightroom
-- Parámetro: photo (objeto LrPhoto)
-- Retorna: tabla con estructura de EXIF compatible con la API
function ExifService.extractExifData(photo)
    -- TEMPORALMENTE DEVUELVE VACÍO - Implementación real comentada abajo
    local exifData = {
        dateTaken = nil,
        camera = {
            make = nil,
            model = nil,
            lens = nil
        },
        settings = {
            focalLength = nil,
            aperture = nil,
            exposureTime = nil,
            iso = nil
        },
        gps = nil
    }
    
    return exifData
    
    -- IMPLEMENTACIÓN REAL (comentada temporalmente):
    --[[
    -- Extraer fecha
    local dateTimeOriginal = photo:getRawMetadata("dateTimeOriginal")
    if dateTimeOriginal then
        exifData.dateTaken = toISODate(dateTimeOriginal)
    else
        local dateTime = photo:getRawMetadata("dateTime")
        if dateTime then
            exifData.dateTaken = toISODate(dateTime)
        end
    end
    
    -- Extraer datos de cámara
    exifData.camera.make = photo:getRawMetadata("cameraMake")
    exifData.camera.model = photo:getRawMetadata("cameraModel")
    exifData.camera.lens = photo:getRawMetadata("lens")
    
    -- Extraer configuraciones
    exifData.settings.focalLength = photo:getRawMetadata("focalLength")
    exifData.settings.aperture = photo:getRawMetadata("aperture")
    exifData.settings.exposureTime = photo:getRawMetadata("shutterSpeed")
    exifData.settings.iso = photo:getRawMetadata("isoSpeedRating")
    
    -- Extraer GPS si existe
    local gpsLatitude = photo:getRawMetadata("gpsLatitude")
    local gpsLongitude = photo:getRawMetadata("gpsLongitude")
    
    if gpsLatitude and gpsLongitude then
        exifData.gps = {
            latitude = gpsLatitude,
            longitude = gpsLongitude,
            altitude = photo:getRawMetadata("gpsAltitude")
        }
    end
    ]]--
end

-- Función MOCK para pruebas (datos inventados)
-- Retorna: tabla con estructura de EXIF de prueba
function ExifService.getMockExifData()
    -- Generar datos aleatorios pero realistas
    local cameras = {
        { make = "Canon", model = "EOS R5", lens = "RF 24-70mm F2.8 L IS USM" },
        { make = "Nikon", model = "Z9", lens = "NIKKOR Z 24-70mm f/2.8 S" },
        { make = "Sony", model = "A7R V", lens = "FE 24-70mm F2.8 GM II" },
        { make = "Fujifilm", model = "X-T5", lens = "XF 16-55mm F2.8 R LM WR" },
    }
    
    local focalLengths = { 24, 35, 50, 70, 85, 100 }
    local apertures = { 1.4, 1.8, 2.0, 2.8, 4.0, 5.6 }
    local exposureTimes = { 0.0005, 0.001, 0.002, 0.004, 0.008, 0.016, 0.033 } -- 1/2000, 1/1000, 1/500, etc
    local isos = { 100, 200, 400, 800, 1600, 3200 }
    
    local selectedCamera = cameras[math.random(#cameras)]
    
    local exifData = {
        dateTaken = os.date("!%Y-%m-%dT%H:%M:%S.000Z", os.time() - math.random(0, 365 * 24 * 3600)),
        camera = {
            make = selectedCamera.make,
            model = selectedCamera.model,
            lens = selectedCamera.lens
        },
        settings = {
            focalLength = focalLengths[math.random(#focalLengths)],
            aperture = apertures[math.random(#apertures)],
            exposureTime = exposureTimes[math.random(#exposureTimes)],
            iso = isos[math.random(#isos)]
        },
        gps = nil -- Por defecto no incluir GPS
    }
    
    -- 30% de probabilidad de tener GPS
    if math.random() < 0.3 then
        exifData.gps = {
            latitude = math.random(-90, 90) + math.random(),
            longitude = math.random(-180, 180) + math.random(),
            altitude = math.random(0, 3000)
        }
    end
    
    return exifData
end

return ExifService
