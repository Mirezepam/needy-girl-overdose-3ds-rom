-- Sub-windows of the original desktop (pills, games...) opened by events: show the matching
-- action category so the player can act on the bottom screen.
local G = require("runtime.gfx")
local T = require("ui.theme")
local c = T.c

local M = { icon = "icon_desktop_okusuri" }
local MAP = { Pills = "okusuri", PillDypass = "okusuri", PillPuron = "okusuri", PillHipron = "okusuri", PillHappa = "okusuri",
              PillPsyche = "okusuri", PillPuron_Horror = "okusuri", Entame = "ame", Internet = "internet", Asobu = "ame", AsobuNeedy = "ame", AsobuLust = "ame" }

function M.draw(win, x0, y0, w0, h0)
  local cat = MAP[win.app] or "ame"
  local list = require("ui.bottom").MENUS[cat]
  local x, y, w, h = T.window(x0 + 2, y0 + 2, w0 - 4, h0 - 2, win.app)
  if win.closeable and T.close("tasks_close") then
    WindowManager:Close(win) return
  end
  for i, a in ipairs(list) do
    local ok, title = pcall(CommandHelper.GetCommandTitle_3, a, Settings.CurrentLanguage.Value)
    if not ok then title = nil end
    if T.button("task_" .. a, x + 4, y + 4 + (i - 1) * 24, w - 8, 22, (title and title ~= NULL) and title or a) then
      WindowManager:Close(win)
      CommandManager:CommandAction_2(a)
    end
  end
end

return M
