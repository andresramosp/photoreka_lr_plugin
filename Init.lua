-- Archivo de inicialización del plugin Photoreka
-- Configuración de logging global

local LrLogger = import 'LrLogger'
local LrTasks = import 'LrTasks'

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


