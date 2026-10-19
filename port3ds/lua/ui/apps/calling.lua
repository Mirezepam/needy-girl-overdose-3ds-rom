-- Incoming JINE call: Ame on the top screen, the call UI on the bottom.
local core = require("runtime.core")
local G = require("runtime.gfx")
local T = require("ui.theme")
local c = T.c

local M = { icon = "icon_taskbar_jine" }

function M.draw(win, x0, y0, w0, h0)
  G.rect(0, 0, 320, 220, 0x3a2a5aff)
  G.draw("icon_jine_ame", 160, 60, { ax = 0.5, ay = 0.5, scale = 2 })
  G.text_center("Ame", 160, 100, c.white)
  local pulse = math.floor((math.sin(core.now() * 8) * 0.5 + 0.5) * 255)
  G.rect(130, 140, 60, 40, 0x40e080 * 256 + 255)
  G.frame_rect(126, 136, 68, 48, 0xffffff00 + pulse, 2)
  G.text_center("JINE", 160, 154, c.white)
end

return M
