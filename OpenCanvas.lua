-- OpenCanvas.lua
-- Abre Canvas de Photoreka en el navegador web

local LrHttp = import 'LrHttp'
local LrTasks = import 'LrTasks'

LrTasks.startAsyncTask(function()
    LrHttp.openUrlInBrowser("https://www.photoreka.com/canvas")
end)