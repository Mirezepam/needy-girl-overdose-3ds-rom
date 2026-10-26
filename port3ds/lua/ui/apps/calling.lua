-- Incoming JINE call: Ame on the top screen, the call UI on the bottom.
local core = require("runtime.core")
local G = require("runtime.gfx")
local T = require("ui.theme")
local c = T.c

local M = { icon = "icon_taskbar_jine" }

function M.draw(win, x0, y0, w0, h0)
  G.rect(0, 0, 320, 220, 0x000000ff)   -- the whole desktop, down to the taskbar
  local x, y, w, h = T.window(50, 30, 220, 140, T.st("Window_Calling", "JINE"), "icon_taskbar_jine")
  G.rect(x, y, w, h, 0x1d1a24ff)
  G.draw("icon_jine_ame", x + w / 2, y + 36, { ax = 0.5, ay = 0.5, fit = { 48, 48 } })
  -- the five green dots of the call art, lighting up one after another
  local k = math.floor(core.now() * 5) % 6
  for i = 0, 4 do
    G.rect(x + w / 2 - 34 + i * 14, y + 70, 6, 6, i < k and 0x2bd94aff or 0x1f5a2bff)
  end
  G.text_center("Ame", x + w / 2, y + 86, c.white)
end

return M
