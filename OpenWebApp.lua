-- OpenWebApp.lua
-- Abre Photo Hub de Photoreka en el navegador web

local LrHttp = import 'LrHttp'
local LrTasks = import 'LrTasks'
local Config = require 'Config'
local ApiService = require 'ApiService'

LrTasks.startAsyncTask(function()
    local handoffToken = ApiService.createHandoff()
    local url = Config.APP_BASE_URL .. '/workspace'
    if handoffToken then
        url = url .. '?lr_handoff=' .. handoffToken
    end
    LrHttp.openUrlInBrowser(url)
end)