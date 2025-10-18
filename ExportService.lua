-- ExportService.lua - Servicio de exportación de fotos
local LrExportSession = import 'LrExportSession'
local LrPathUtils = import 'LrPathUtils'
local LrFileUtils = import 'LrFileUtils'

local ExportService = {}

-- Crea una carpeta temporal para las exportaciones
function ExportService.createTempFolder()
    local tempFolder = LrPathUtils.getStandardFilePath('temp')
    local exportFolder = LrPathUtils.child(tempFolder, 'PhotorekaExport_' .. os.time())
    LrFileUtils.createDirectory(exportFolder)
    return exportFolder
end

-- Configuración de exportación predeterminada
function ExportService.getExportSettings(exportFolder)
    return {
        LR_export_destinationType = 'specificFolder',
        LR_export_destinationPathPrefix = exportFolder,
        LR_format = 'JPEG',
        LR_jpeg_quality = 0.9,
        LR_size_doConstrain = true,
        LR_size_maxWidth = 1500,
        LR_size_maxHeight = 1500,
        LR_size_resolution = 72,
        LR_size_resolutionUnits = 'inch',
        LR_reimportExportedPhoto = false,
        LR_export_colorSpace = 'sRGB',
    }
end

-- Exporta las fotos en dos versiones (full y thumb) y reporta progreso
-- Parámetros:
--   photos: array de fotos a exportar
--   exportFolder: carpeta de destino
--   progressCallback: función que recibe (current, total, caption)
-- Retorna: tabla con {fullPhotos = {...}, thumbPhotos = {...}}
function ExportService.exportPhotos(photos, exportFolder, progressCallback)
    local fullPhotos = {}
    local thumbPhotos = {}
    local totalPhotos = #photos
    local currentPhoto = 0
    
    -- FASE 1: Exportar versión FULL (1500px)
    local fullSettings = {
        LR_export_destinationType = 'specificFolder',
        LR_export_destinationPathPrefix = LrPathUtils.child(exportFolder, 'full'),
        LR_format = 'JPEG',
        LR_jpeg_quality = 0.9,
        LR_size_doConstrain = true,
        LR_size_maxWidth = 1500,
        LR_size_maxHeight = 1500,
        LR_size_resolution = 72,
        LR_size_resolutionUnits = 'inch',
        LR_reimportExportedPhoto = false,
        LR_export_colorSpace = 'sRGB',
    }
    
    LrFileUtils.createDirectory(fullSettings.LR_export_destinationPathPrefix)
    
    local fullSession = LrExportSession({
        photosToExport = photos,
        exportSettings = fullSettings,
    })
    
    for _, rendition in fullSession:renditions() do
        currentPhoto = currentPhoto + 1
        
        if progressCallback then
            progressCallback(
                currentPhoto,
                totalPhotos * 2, -- Total incluye ambas versiones
                string.format('Exportando versión full %d de %d...', currentPhoto, totalPhotos)
            )
        end
        
        local success, pathOrMessage = rendition:waitForRender()
        
        if success then
            table.insert(fullPhotos, pathOrMessage)
        end
    end
    
    -- FASE 2: Exportar versión THUMBNAIL (800px)
    local thumbSettings = {
        LR_export_destinationType = 'specificFolder',
        LR_export_destinationPathPrefix = LrPathUtils.child(exportFolder, 'thumbs'),
        LR_format = 'JPEG',
        LR_jpeg_quality = 0.85,
        LR_size_doConstrain = true,
        LR_size_maxWidth = 800,
        LR_size_maxHeight = 800,
        LR_size_resolution = 72,
        LR_size_resolutionUnits = 'inch',
        LR_reimportExportedPhoto = false,
        LR_export_colorSpace = 'sRGB',
    }
    
    LrFileUtils.createDirectory(thumbSettings.LR_export_destinationPathPrefix)
    
    local thumbSession = LrExportSession({
        photosToExport = photos,
        exportSettings = thumbSettings,
    })
    
    for _, rendition in thumbSession:renditions() do
        currentPhoto = currentPhoto + 1
        
        if progressCallback then
            progressCallback(
                currentPhoto,
                totalPhotos * 2, -- Total incluye ambas versiones
                string.format('Exportando thumbnail %d de %d...', currentPhoto - totalPhotos, totalPhotos)
            )
        end
        
        local success, pathOrMessage = rendition:waitForRender()
        
        if success then
            table.insert(thumbPhotos, pathOrMessage)
        end
    end
    
    return {
        fullPhotos = fullPhotos,
        thumbPhotos = thumbPhotos
    }
end

return ExportService
