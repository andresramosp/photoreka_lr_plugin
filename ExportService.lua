-- ExportService.lua - Servicio de exportación de fotos
local LrExportSession = import 'LrExportSession'
local LrPathUtils = import 'LrPathUtils'
local LrFileUtils = import 'LrFileUtils'
local LrLogger = import 'LrLogger'
local LrTasks = import 'LrTasks'

local Config = require 'Config'

local ExportService = {}

local log = LrLogger('PhotorekaPlugin')
log:enable("logfile")

-- Crea una carpeta temporal para las exportaciones
function ExportService.createTempFolder()
    local tempFolder = LrPathUtils.getStandardFilePath('temp')
    local exportFolder = LrPathUtils.child(tempFolder, 'PhotorekaExport_' .. os.time())
    LrFileUtils.createDirectory(exportFolder)
    return exportFolder
end

-- Elimina una carpeta y todo su contenido de forma recursiva
function ExportService.deleteTempFolder(folderPath)
    if folderPath and LrFileUtils.exists(folderPath) then
        LrFileUtils.delete(folderPath)
    end
end

local function getFileSizeBytes(filePath)
    local file = io.open(filePath, 'rb')
    if not file then
        error('No se pudo abrir el archivo exportado: ' .. tostring(filePath))
    end

    local size = file:seek('end')
    file:close()

    return size or 0
end

local function buildExportSettings(exportFolder, maxWidth, maxHeight, quality)
    return {
        LR_export_destinationType = 'specificFolder',
        LR_export_destinationPathPrefix = exportFolder,
        LR_format = 'JPEG',
        LR_jpeg_quality = quality,
        LR_size_doConstrain = true,
        LR_size_maxWidth = maxWidth,
        LR_size_maxHeight = maxHeight,
        LR_size_resolution = 72,
        LR_size_resolutionUnits = 'inch',
        LR_reimportExportedPhoto = false,
        LR_export_colorSpace = 'sRGB',
    }
end

local function exportSinglePhoto(photo, exportFolder, maxWidth, maxHeight, quality)
    local exportSession = LrExportSession({
        photosToExport = { photo },
        exportSettings = buildExportSettings(exportFolder, maxWidth, maxHeight, quality),
    })

    for _, rendition in exportSession:renditions() do
        local success, pathOrMessage = rendition:waitForRender()

        if success then
            return pathOrMessage
        end

        error('Failed to export photo: ' .. tostring(pathOrMessage))
    end

    error('Failed to export photo: no rendition returned')
end

local function calculateNextQuality(currentQuality, currentSize, targetSize)
    local ratio = targetSize / currentSize
    local nextQuality = currentQuality * math.sqrt(ratio)

    if nextQuality >= currentQuality then
        nextQuality = currentQuality - (Config.EXPORT_JPEG_QUALITY_DECREMENT / 2)
    end

    nextQuality = math.max(Config.EXPORT_JPEG_QUALITY_MIN, nextQuality)

    return math.floor((nextQuality * 100) + 0.5) / 100
end

local function exportPhotoWithSizeCap(photo, exportFolder, maxWidth, maxHeight, maxSizeBytes, variantLabel, photoIndex)
    LrFileUtils.createDirectory(exportFolder)

    local acceptedMaxSizeBytes = math.floor(maxSizeBytes * Config.EXPORT_SIZE_TOLERANCE_RATIO)
    local quality = Config.EXPORT_JPEG_QUALITY_INITIAL
    local attempts = 0
    local finalPath = nil
    local finalSize = 0

    while true do
        attempts = attempts + 1

        if finalPath and LrFileUtils.exists(finalPath) then
            LrFileUtils.delete(finalPath)
        end

        finalPath = exportSinglePhoto(photo, exportFolder, maxWidth, maxHeight, quality)
        finalSize = getFileSizeBytes(finalPath)

        log:info(string.format(
            '%s photo %d attempt %d: quality=%.2f size=%d bytes',
            variantLabel,
            photoIndex,
            attempts,
            quality,
            finalSize
        ))

        if not Config.EXPORT_ENABLE_QUALITY_REDUCTION then
            log:info(string.format(
                '%s photo %d quality reduction disabled; keeping initial export',
                variantLabel,
                photoIndex
            ))
            return finalPath
        end

        if finalSize <= acceptedMaxSizeBytes then
            return finalPath
        end

        if attempts >= Config.EXPORT_MAX_ATTEMPTS or quality <= Config.EXPORT_JPEG_QUALITY_MIN then
            log:warn(string.format(
                '%s photo %d exceeds target size after %d attempts: %d > %d bytes',
                variantLabel,
                photoIndex,
                attempts,
                finalSize,
                maxSizeBytes
            ))
            return finalPath
        end

        quality = calculateNextQuality(quality, finalSize, maxSizeBytes)
    end
end

-- Configuración de exportación predeterminada
function ExportService.getExportSettings(exportFolder)
    return buildExportSettings(
        exportFolder,
        Config.EXPORT_FULL_MAX_WIDTH,
        Config.EXPORT_FULL_MAX_HEIGHT,
        Config.EXPORT_JPEG_QUALITY_INITIAL
    )
end

local function exportVariantPhotos(photos, targetPaths, variantConfig, onPhotoExported)
    for i, photo in ipairs(photos) do
        local targetFolder = variantConfig.getFolder(i)
        local success, result = LrTasks.pcall(function()
            return exportPhotoWithSizeCap(
                photo,
                targetFolder,
                variantConfig.maxWidth,
                variantConfig.maxHeight,
                variantConfig.maxSizeBytes,
                variantConfig.label,
                i
            )
        end)

        if success then
            targetPaths[i] = result
        else
            targetPaths[i] = nil

            if targetFolder and LrFileUtils.exists(targetFolder) then
                LrFileUtils.delete(targetFolder)
            end

            log:warn(string.format(
                '%s photo %d skipped during export: %s',
                variantConfig.label,
                i,
                tostring(result)
            ))
        end

        if onPhotoExported then
            onPhotoExported(i)
        end
    end
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
    local completedExports = 0
    local fullRoot = LrPathUtils.child(exportFolder, 'full')
    local thumbRoot = LrPathUtils.child(exportFolder, 'thumbs')
    local totalExports = totalPhotos * 2

    LrFileUtils.createDirectory(fullRoot)
    LrFileUtils.createDirectory(thumbRoot)

    local function reportProgress(caption)
        completedExports = completedExports + 1

        if progressCallback then
            progressCallback(completedExports, totalExports, caption)
        end
    end

    local fullVariant = {
        label = 'Full',
        maxWidth = Config.EXPORT_FULL_MAX_WIDTH,
        maxHeight = Config.EXPORT_FULL_MAX_HEIGHT,
        maxSizeBytes = Config.EXPORT_FULL_MAX_SIZE_BYTES,
        getFolder = function(i)
            return LrPathUtils.child(fullRoot, string.format('photo_%04d', i))
        end,
    }

    local thumbVariant = {
        label = 'Thumbnail',
        maxWidth = Config.EXPORT_THUMB_MAX_WIDTH,
        maxHeight = Config.EXPORT_THUMB_MAX_HEIGHT,
        maxSizeBytes = Config.EXPORT_THUMB_MAX_SIZE_BYTES,
        getFolder = function(i)
            return LrPathUtils.child(thumbRoot, string.format('photo_%04d', i))
        end,
    }

    if not Config.EXPORT_PARALLEL_VARIANTS then
        exportVariantPhotos(photos, fullPhotos, fullVariant, function(i)
            reportProgress(string.format('Exporting photo %d de %d...', i, totalPhotos))
        end)

        exportVariantPhotos(photos, thumbPhotos, thumbVariant, function(i)
            reportProgress(string.format('Exporting thumbnail %d de %d...', i, totalPhotos))
        end)

        return {
            fullPhotos = fullPhotos,
            thumbPhotos = thumbPhotos,
            totalCount = totalPhotos
        }
    end

    local tasksCompleted = 0
    local taskErrors = {}

    local function runVariantTask(targetPaths, variantConfig, progressLabel)
        LrTasks.startAsyncTask(function()
            local success, err = LrTasks.pcall(function()
                exportVariantPhotos(photos, targetPaths, variantConfig, function(i)
                    reportProgress(string.format(progressLabel, i, totalPhotos))
                end)
            end)

            if not success then
                table.insert(taskErrors, err)
                log:error(string.format('%s export task failed: %s', variantConfig.label, tostring(err)))
            end

            tasksCompleted = tasksCompleted + 1
        end)
    end

    runVariantTask(fullPhotos, fullVariant, 'Exporting photo %d de %d...')
    runVariantTask(thumbPhotos, thumbVariant, 'Exporting thumbnail %d de %d...')

    while tasksCompleted < 2 do
        LrTasks.sleep(0.05)
    end

    if #taskErrors > 0 then
        error(taskErrors[1])
    end

    return {
        fullPhotos = fullPhotos,
        thumbPhotos = thumbPhotos,
        totalCount = totalPhotos
    }
end

return ExportService
