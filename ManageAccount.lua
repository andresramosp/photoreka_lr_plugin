-- ManageAccount.lua - Gestión de cuenta de usuario
local LrTasks = import 'LrTasks'
local LrDialogs = import 'LrDialogs'
local LrLogger = import 'LrLogger'

local AuthService = require 'AuthService'

local log = LrLogger('PhotorekaPlugin')
log:enable("logfile")

LrTasks.startAsyncTask(function()
    log:info("Abriendo gestión de cuenta")
    
    local token = AuthService.getStoredToken()
    
    if token then
        -- Si hay sesión activa, mostrar diálogo de cuenta
        AuthService.showAccountDialog()
    else
        -- Si no hay sesión, mostrar diálogo de login
        local loginToken = AuthService.showLoginDialog()
        
        if loginToken then
            log:info("Login exitoso")
            LrDialogs.message(
                "Welcome to Photoreka!",
                "You are now signed in and ready to use all Photoreka features.",
                "info"
            )
        else
            log:info("Usuario canceló el login")
        end
    end
end)
