-- ControlPanel window: the same panel as Start menu > Control panel
local M = { icon = "icon_gear" }

function M.draw(win)
  require("ui.apps.pause").control_panel(function() WindowManager:Close(win) end)
end

return M
