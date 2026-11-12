-- ScreeningService.lua - Quick screening: resizes the photos and sends them to the API in sheets.
-- The photos never become Photoreka photos: each sheet comes back with one class per photo
-- (failed / passed / standout) and the caller marks them in the catalog.
-- Contract of the API endpoints: api/SCREENING.md in the Photoreka repository.
local LrTasks = import 'LrTasks'
local LrHttp = import 'LrHttp'
local LrExportSession = import 'LrExportSession'
local LrFileUtils = import 'LrFileUtils'
local LrPathUtils = import 'LrPathUtils'
local LrStringUtils = import 'LrStringUtils'
local LrLogger = import 'LrLogger'

local JSON = require 'JSON'
local Config = require 'Config'
local AuthService = require 'AuthService'

local log = LrLogger('PhotorekaPlugin')
log:enable("logfile")

local ScreeningService = {}

-- Long edge of the copy sent to the API. A cell of the contact sheet is about 290 px wide,
-- so 512 px is plenty and keeps each photo around 50 KB.
ScreeningService.IMAGE_MAX_SIDE = 512
ScreeningService.JPEG_QUALITY = 0.75
-- Sheets in flight at once. Each one is a single model call of 5-10 seconds.
ScreeningService.CONCURRENT_SHEETS = 3
ScreeningService.SHEET_ATTEMPTS = 2
ScreeningService.HTTP_TIMEOUT_SECONDS = 120

ScreeningService.CLASSES = { 'failed', 'passed', 'standout' }

local tempFolderCounter = 0

local function createTempFolder()
    tempFolderCounter = tempFolderCounter + 1
    local folder = LrPathUtils.child(
        LrPathUtils.getStandardFilePath('temp'),
        string.format('PhotorekaScreening_%d_%d', os.time(), tempFolderCounter)
    )
    LrFileUtils.createDirectory(folder)
    return folder
end

local function readAndDelete(path)
    local file = io.open(path, 'rb')
    if not file then return nil end
    local data = file:read('*all')
    file:close()
    LrFileUtils.delete(path)
    return data
end

local function statusOf(headers)
    return headers and tonumber(headers.status) or nil
end

local function exportSettings(folder)
    return {
        LR_export_destinationType = 'specificFolder',
        LR_export_destinationPathPrefix = folder,
        LR_export_useSubfolder = false,
        LR_collisionHandling = 'rename',
        LR_format = 'JPEG',
        LR_jpeg_quality = ScreeningService.JPEG_QUALITY,
        LR_export_colorSpace = 'sRGB',
        LR_size_doConstrain = true,
        LR_size_doNotEnlarge = true,
        LR_size_maxWidth = ScreeningService.IMAGE_MAX_SIDE,
        LR_size_maxHeight = ScreeningService.IMAGE_MAX_SIDE,
        LR_size_resolution = 72,
        LR_size_resolutionUnits = 'inch',
        LR_outputSharpeningOn = false,
        LR_minimizeEmbeddedMetadata = true,
        LR_reimportExportedPhoto = false,
    }
end

-- Cost of screening `count` photos, the user's balance and the sheet limits.
-- Returns { photos, minPhotos, maxPhotosPerSheet, creditsPerPhoto, credits, remaining, affordable }.
function ScreeningService.getQuote(token, count)
    local url = string.format('%s/api/screening/quote?count=%d', Config.API_BASE_URL, count)
    local body, headers = LrHttp.get(url, {
        { field = 'Authorization', value = 'Bearer ' .. token },
    }, 30)
    local status = statusOf(headers)
    if status == 401 then
        AuthService.invalidateToken()
        error('Your session has expired. Please log in again.')
    end
    if not body or status ~= 200 then
        error(string.format('Could not get the screening price (status %s)', tostring(status)))
    end
    return JSON.decode(body)
end

-- One sheet. Returns { status = 'ok', data = {...} } or { status = 'credits' | 'auth' | 'failed' }.
local function postSheet(token, images)
    local body = JSON.encode({ images = images })
    local headers = {
        { field = 'Authorization', value = 'Bearer ' .. token },
        { field = 'Content-Type', value = 'application/json' },
    }
    for attempt = 1, ScreeningService.SHEET_ATTEMPTS do
        local response, responseHeaders = LrHttp.post(
            Config.API_BASE_URL .. '/api/screening/sheet',
            body,
            headers,
            'POST',
            ScreeningService.HTTP_TIMEOUT_SECONDS
        )
        local status = statusOf(responseHeaders)
        if status == 200 and response then
            return { status = 'ok', data = JSON.decode(response) }
        end
        if status == 402 then return { status = 'credits' } end
        if status == 401 then
            AuthService.invalidateToken()
            return { status = 'auth' }
        end
        log:warn(string.format('Screening sheet attempt %d failed (status %s): %s',
            attempt, tostring(status), tostring(response)))
        if attempt < ScreeningService.SHEET_ATTEMPTS then LrTasks.sleep(2) end
    end
    return { status = 'failed' }
end

-- Resizes `photos` and screens them in sheets of `sheetSize`, both at once: a sheet goes
-- out as soon as it is full while the next photos are still being resized.
-- Parameters:
--   photos: array of LrPhoto
--   options.token: API token
--   options.sheetSize: photos per sheet (quote.maxPhotosPerSheet)
--   options.isCanceled: function returning true when the user pressed Cancel
--   options.onProgress: function(state) called after every photo resized or screened
-- Returns state:
--   results[i]: class of photos[i] ('failed' | 'passed' | 'standout') or nil when unscreened
--   resized, screened, creditsCharged, remaining, failedSheets,
--   stopReason: nil | 'canceled' | 'credits' | 'auth'
function ScreeningService.screen(photos, options)
    local state = {
        total = #photos,
        resized = 0,
        screened = 0,
        inFlight = 0,
        creditsCharged = 0,
        remaining = nil,
        failedSheets = 0,
        stopReason = nil,
        results = {},
    }
    local function progress()
        if options.onProgress then options.onProgress(state) end
    end

    local indexByPhoto = {}
    for i, photo in ipairs(photos) do indexByPhoto[photo.localIdentifier] = i end

    local function send(sheet)
        state.inFlight = state.inFlight + 1
        LrTasks.startAsyncTask(function()
            local ok, err = LrTasks.pcall(function()
                local images = {}
                for k, item in ipairs(sheet) do images[k] = item.data end
                local reply = postSheet(options.token, images)
                if reply.status == 'ok' then
                    local classes = reply.data.classes or {}
                    for k, item in ipairs(sheet) do
                        local value = classes[k]
                        if value and value ~= 'unscreened' then state.results[item.index] = value end
                    end
                    state.creditsCharged = state.creditsCharged + (reply.data.creditsCharged or 0)
                    state.remaining = reply.data.remaining or state.remaining
                elseif reply.status == 'credits' or reply.status == 'auth' then
                    state.stopReason = state.stopReason or reply.status
                else
                    state.failedSheets = state.failedSheets + 1
                end
            end)
            if not ok then
                log:error('Screening sheet failed: ' .. tostring(err))
                state.failedSheets = state.failedSheets + 1
            end
            state.screened = state.screened + #sheet
            state.inFlight = state.inFlight - 1
            progress()
        end)
    end

    local buffer = {}
    local function flush()
        if #buffer == 0 then return end
        while state.inFlight >= ScreeningService.CONCURRENT_SHEETS and not state.stopReason do
            LrTasks.sleep(0.1)
        end
        if state.stopReason then return end
        local sheet = buffer
        buffer = {}
        send(sheet)
    end

    local folder = createTempFolder()
    local session = LrExportSession({
        photosToExport = photos,
        exportSettings = exportSettings(folder),
    })

    for _, rendition in session:renditions() do
        if state.stopReason then break end
        if options.isCanceled and options.isCanceled() then
            state.stopReason = 'canceled'
            break
        end
        local success, pathOrMessage = rendition:waitForRender()
        local index = indexByPhoto[rendition.photo.localIdentifier]
        if success and index then
            local data = readAndDelete(pathOrMessage)
            if data then
                table.insert(buffer, { index = index, data = LrStringUtils.encodeBase64(data) })
            end
        else
            log:warn('Screening: photo could not be resized: ' .. tostring(pathOrMessage))
            -- An unreadable photo counts as done for the progress bar.
            state.screened = state.screened + 1
        end
        state.resized = state.resized + 1
        progress()
        if #buffer >= options.sheetSize then flush() end
    end
    if not state.stopReason then flush() end

    -- Sheets already sent finish even after Cancel: they are paid once they reach the API.
    while state.inFlight > 0 do
        LrTasks.sleep(0.2)
    end
    LrFileUtils.delete(folder)
    return state
end

return ScreeningService
