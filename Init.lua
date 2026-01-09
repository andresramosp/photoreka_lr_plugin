-- Archivo de inicialización del plugin Photoreka
-- Configuración de logging global

local LrLogger = import 'LrLogger'
local LrTasks = import 'LrTasks'
local LrDialogs = import 'LrDialogs'

-- Configurar logger global del plugin
local log = LrLogger('PhotorekaPlugin')
log:enable("logfile")
log:info("========================================")
log:info("PHOTOREKA PLUGIN INICIADO")
log:info("========================================")
log:info("Logger configurado correctamente")
log:info("========================================")

-- Nota: El log se guarda automáticamente en:
-- Windows: C:\Users\[usuario]\AppData\Roaming\Adobe\Lightroom\Logs\PhotorekaPlugin.log
-- macOS: ~/Library/Logs/Adobe/Lightroom/PhotorekaPlugin.log

-- Verificar autenticación al iniciar el plugin
LrTasks.startAsyncTask(function()
    local AuthService = require 'AuthService'
    
    -- Verificar si hay un token almacenado
    local token = AuthService.getStoredToken()
    
    if not token then
        log:info("No se encontró sesión activa - abriendo diálogo de login")
        -- Esperar un momento para que Lightroom termine de cargar
        LrTasks.sleep(1)
        local loginToken = AuthService.showLoginDialog()
        if loginToken then
            log:info("Login exitoso durante inicialización del plugin")
            LrDialogs.message(
                "Welcome to Photoreka!",
                "You are now signed in and ready to use all Photoreka features.",
                "info"
            )
        else
            log:info("Usuario canceló el login durante inicialización")
        end
    else
        log:info("Sesión activa encontrada - usuario ya autenticado")
        local userInfo = AuthService.getStoredUserInfo()
        if userInfo then
            log:info("Usuario: " .. (userInfo.email or "desconocido"))
        end
    end
end)


