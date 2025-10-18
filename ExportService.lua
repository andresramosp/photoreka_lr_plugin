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

-- Exporta las fotos y reporta progreso
-- Parámetros:
--   photos: array de fotos a exportar
--   exportSettings: configuración de exportación
--   progressCallback: función que recibe (current, total, caption)
-- Retorna: array de rutas de archivos exportados
function ExportService.exportPhotos(photos, exportSettings, progressCallback)
    local exportSession = LrExportSession({
        photosToExport = photos,
        exportSettings = exportSettings,
    })
    
    local exportedFiles = {}
    local totalPhotos = #photos
    local currentPhoto = 0
    
    for _, rendition in exportSession:renditions() do
        currentPhoto = currentPhoto + 1
        
        if progressCallback then
            progressCallback(
                currentPhoto,
                totalPhotos,
                string.format('Exportando foto %d de %d...', currentPhoto, totalPhotos)
            )
        end
        
        local success, pathOrMessage = rendition:waitForRender()
        
        if success then
            table.insert(exportedFiles, pathOrMessage)
        end
    end
    
    return exportedFiles
end

return ExportService
