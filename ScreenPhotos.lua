-- ScreenPhotos.lua - "Quick Screening": marks the selected photos as failed, passed or standout
-- with a quick, low-cost glance, so the photographer can decide what is worth analysing.
-- The photos are resized locally and sent in sheets; they are not uploaded to Photoreka.
local LrTasks = import 'LrTasks'
local LrApplication = import 'LrApplication'
local LrDialogs = import 'LrDialogs'
local LrView = import 'LrView'
local LrBinding = import 'LrBinding'
local LrFunctionContext = import 'LrFunctionContext'
local LrLogger = import 'LrLogger'

local AuthService = require 'AuthService'
local ScreeningService = require 'ScreeningService'

local log = LrLogger('PhotorekaPlugin')
log:enable("logfile")

local TITLE = 'Quick Screening'
local METADATA_FIELD = 'photorekascreening'
local KEYWORD_PARENT = 'Photoreka Screening'
local KEYWORD_NAMES = { failed = 'Failed', passed = 'Passed', standout = 'Standout' }
-- Only the two classes worth a glance get a color; "passed" keeps the photo's own label.
local COLOR_LABELS = { failed = 'red', standout = 'green' }

local function formatCredits(value)
    return string.format('%.1f', value or 0)
end

-- Marks every screened photo: always the plugin metadata field (Library Filter ›
-- Metadata › Photoreka Screening), plus the keywords or the color labels the user chose.
local function applyMarks(catalog, photos, results, method)
    local keywords = {}
    if method == 'keywords' then
        -- A keyword created in a write block can only be used as a parent, or added to a
        -- photo, once that block has finished: parent, children and photos go in three blocks.
        catalog:withWriteAccessDo('Create Photoreka screening keyword', function()
            catalog:createKeyword(KEYWORD_PARENT, {}, false, nil, true)
        end, { timeout = 30 })
        catalog:withWriteAccessDo('Create Photoreka screening keywords', function()
            local parent = catalog:createKeyword(KEYWORD_PARENT, {}, false, nil, true)
            for _, class in ipairs(ScreeningService.CLASSES) do
                catalog:createKeyword(KEYWORD_NAMES[class], {}, false, parent, true)
            end
        end, { timeout = 30 })
    end

    catalog:withWriteAccessDo('Photoreka Quick Screening', function()
        if method == 'keywords' then
            local parent = catalog:createKeyword(KEYWORD_PARENT, {}, false, nil, true)
            for _, class in ipairs(ScreeningService.CLASSES) do
                keywords[class] = catalog:createKeyword(KEYWORD_NAMES[class], {}, false, parent, true)
            end
        end
        for i, photo in ipairs(photos) do
            local class = results[i]
            if class then
                photo:setPropertyForPlugin(_PLUGIN, METADATA_FIELD, class)
                if method == 'keywords' then
                    -- A photo screened again keeps only its latest class.
                    for other, keyword in pairs(keywords) do
                        if other ~= class then photo:removeKeyword(keyword) end
                    end
                    photo:addKeyword(keywords[class])
                elseif COLOR_LABELS[class] then
                    photo:setRawMetadata('colorNameForLabel', COLOR_LABELS[class])
                end
            end
        end
    end, { timeout = 60 })
end

local function showResult(f, state, toScreenCount, method)
    local counts = { failed = 0, passed = 0, standout = 0 }
    local screened = 0
    for _, class in pairs(state.results) do
        counts[class] = counts[class] + 1
        screened = screened + 1
    end

    local status
    if state.stopReason == 'credits' then
        status = '⚠ Stopped: you ran out of credits.'
    elseif state.stopReason == 'auth' then
        status = '⚠ Stopped: your session expired. Log in again and screen the rest.'
    elseif state.stopReason == 'canceled' then
        status = 'Canceled. The photos already screened keep their marks.'
    elseif screened < toScreenCount then
        status = '⚠ Screening finished with errors.'
    else
        status = '✓ Screening finished.'
    end

    local howToFilter = method == 'keywords'
        and 'Filter them with the keywords under "Photoreka Screening", or in Library Filter › Metadata › Photoreka Screening.'
        or 'Failed photos are labeled red and standout photos green. All three classes are also in Library Filter › Metadata › Photoreka Screening.'

    local rows = {
        spacing = f:control_spacing(),
        f:static_text { title = status, font = '<system/bold>' },
        f:separator { fill_horizontal = 1 },
        f:static_text {
            title = string.format('Failed: %d    Passed: %d    Standout: %d', counts.failed, counts.passed, counts.standout),
        },
    }
    if screened < toScreenCount then
        table.insert(rows, f:static_text {
            title = string.format('Not screened: %d (they were not charged; select them and run it again).', toScreenCount - screened),
            font = '<system/small>',
        })
    end
    table.insert(rows, f:static_text {
        title = string.format('Credits used: %s', formatCredits(state.creditsCharged))
            .. (state.remaining and string.format('    Balance: %s', formatCredits(state.remaining)) or ''),
        font = '<system/small>',
    })
    table.insert(rows, f:spacer { height = 6 })
    table.insert(rows, f:static_text { title = howToFilter, width = 460, font = '<system/small>' })

    LrDialogs.presentModalDialog({
        title = TITLE,
        contents = f:column(rows),
        actionVerb = 'Close',
        cancelVerb = '< exclude >',
    })
end

LrTasks.startAsyncTask(function()
LrFunctionContext.callWithContext('quickScreening', function(context)
    local catalog = LrApplication.activeCatalog()
    local photos = {}
    local hasSelection = false
    local alreadyScreened = {}
    local videos = 0

    catalog:withReadAccessDo(function()
        hasSelection = catalog:getTargetPhoto() ~= nil
        for _, photo in ipairs(catalog:getTargetPhotos()) do
            if photo:getRawMetadata('isVideo') then
                videos = videos + 1
            else
                table.insert(photos, photo)
                alreadyScreened[#photos] = photo:getPropertyForPlugin(_PLUGIN, METADATA_FIELD) ~= nil
            end
        end
    end)

    if not hasSelection or #photos == 0 then
        LrDialogs.message(TITLE, 'Select the photos you want to screen first.', 'info')
        return
    end

    local token = AuthService.ensureAuthenticated()
    if not token or token == '' then return end

    local quoteOk, quote = LrTasks.pcall(function()
        return ScreeningService.getQuote(token, #photos)
    end)
    if not quoteOk or not quote then
        LrDialogs.message(TITLE, tostring(quote), 'critical')
        return
    end

    local screenedCount = 0
    for i = 1, #photos do
        if alreadyScreened[i] then screenedCount = screenedCount + 1 end
    end

    local f = LrView.osFactory()
    local props = LrBinding.makePropertyTable(context)
    props.skipScreened = true
    props.method = 'keywords'

    local function refresh()
        local count = props.skipScreened and (#photos - screenedCount) or #photos
        local credits = count * (quote.creditsPerPhoto or 0)
        props.toScreen = count
        props.costText = string.format('Photos to screen: %d    Cost: %s credits    Balance: %s',
            count, formatCredits(credits), formatCredits(quote.remaining))
        if count < (quote.minPhotos or 0) then
            props.warning = string.format('Quick screening works on at least %d photos.', quote.minPhotos)
        elseif credits > (quote.remaining or 0) then
            props.warning = 'You do not have enough credits for these photos.'
        else
            props.warning = ''
        end
        props.canScreen = props.warning == ''
    end
    refresh()
    props:addObserver('skipScreened', refresh)

    local contents = f:column {
        bind_to_object = props,
        spacing = f:control_spacing(),
        width = 480,

        f:static_text {
            title = string.format('Selected photos: %d', #photos)
                .. (videos > 0 and string.format('  (%d videos left out)', videos) or ''),
            font = '<system/bold>',
        },
        f:static_text {
            title = 'A quick glance marks the photos that failed and the ones that stand out, so you can decide what is worth analysing. The marks are suggestions you can review.',
            width = 480,
            font = '<system/small>',
        },
        f:separator { fill_horizontal = 1 },

        f:checkbox {
            title = string.format('Skip the %d photos already screened', screenedCount),
            value = LrView.bind('skipScreened'),
            visible = screenedCount > 0,
        },

        f:row {
            spacing = f:label_spacing(),
            f:static_text { title = 'Mark them with:' },
            f:popup_menu {
                value = LrView.bind('method'),
                items = {
                    { title = 'Keywords (Photoreka Screening › Failed / Passed / Standout)', value = 'keywords' },
                    { title = 'Color labels (red = failed, green = standout)', value = 'colors' },
                },
            },
        },
        f:static_text {
            title = 'Color labels replace the current label of the failed and standout photos. Keywords are never exported with your photos.',
            width = 480,
            font = '<system/small>',
            text_color = LrView.kLabelColor,
        },

        f:separator { fill_horizontal = 1 },
        f:static_text { title = LrView.bind('costText') },
        f:static_text {
            title = LrView.bind('warning'),
            visible = LrView.bind {
                key = 'warning',
                transform = function(value) return value ~= nil and value ~= '' end,
            },
            font = '<system/bold>',
        },
    }

    local answer = LrDialogs.presentModalDialog({
        title = TITLE,
        contents = contents,
        actionVerb = 'Screen',
        actionBinding = { enabled = { bind_to_object = props, key = 'canScreen' } },
    })
    if answer ~= 'ok' then return end

    local method = props.method
    local toScreen = {}
    for i, photo in ipairs(photos) do
        if not (props.skipScreened and alreadyScreened[i]) then table.insert(toScreen, photo) end
    end

    local state
    LrFunctionContext.callWithContext('quickScreeningProgress', function(progressContext)
        local scope = LrDialogs.showModalProgressDialog({
            title = TITLE,
            caption = 'Preparing photos...',
            functionContext = progressContext,
        })
        state = ScreeningService.screen(toScreen, {
            token = token,
            sheetSize = quote.maxPhotosPerSheet or 20,
            isCanceled = function() return scope:isCanceled() end,
            onProgress = function(s)
                -- Resizing and screening each fill half of the bar.
                scope:setPortionComplete(s.resized + s.screened, 2 * s.total)
                scope:setCaption(string.format('Resizing %d/%d    Screened %d/%d',
                    s.resized, s.total, s.screened, s.total))
            end,
        })
        scope:setCaption('Marking photos...')
        local marked, err = LrTasks.pcall(function()
            applyMarks(catalog, toScreen, state.results, method)
        end)
        if not marked then
            log:error('Quick screening: marking failed: ' .. tostring(err))
            state.markError = tostring(err)
        end
        scope:done()
    end)

    if state.markError then
        LrDialogs.message(TITLE, 'The photos were screened but could not be marked: ' .. state.markError, 'critical')
        return
    end
    showResult(f, state, #toScreen, method)
end)
end)
