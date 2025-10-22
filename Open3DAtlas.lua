-- Open3DAtlas.lua
-- Abre 3D Atlas de Photoreka en el navegador web

local LrHttp = import 'LrHttp'
local LrTasks = import 'LrTasks'

LrTasks.startAsyncTask(function()
    LrHttp.openUrlInBrowser("https://www.photoreka.com/atlas")
end)