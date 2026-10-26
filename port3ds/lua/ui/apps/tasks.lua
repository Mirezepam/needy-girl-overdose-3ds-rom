-- Sub-windows of the original desktop (pills, games...) opened by events: show the matching
-- action category so the player can act on the bottom screen.
local core = require("runtime.core")
local G = require("runtime.gfx")
local I = require("runtime.input")
local T = require("ui.theme")
local c = T.c

local M = { icon = "icon_desktop_okusuri" }
local MAP = { Pills = "okusuri", PillDypass = "okusuri", PillPuron = "okusuri", PillHipron = "okusuri", PillHappa = "okusuri",
              PillPsyche = "okusuri", PillPuron_Horror = "okusuri", Entame = "ame", Internet = "internet", Asobu = "ame", AsobuNeedy = "ame", AsobuLust = "ame" }

local PILL = { PillDypass = "dypass", PillPuron = "puron", PillPuron_Horror = "puron", PillHipron = "hyporon",
               PillHappa = "happa", PillPsyche = "psyche" }

-- App_AsobuInran / App_AsobuNeedy (Ending_Lust, Ending_Needy): only three "H" shortcuts are left,
-- labelled like PlayMakeLove; ActionButtonInran / ActionButtonNeedy run Action_Inran / Action_Needy
local SPECIAL = { AsobuLust = "Action_Inran", AsobuNeedy = "Action_Needy" }
local last_special = -10
local function draw_special(win, x0, y0, w0, h0)
  local x, y, w, h = T.window(x0 + 2, y0 + 2, w0 - 4, h0 - 2, T.st("Shortcut_Play", "Play"), "icon_desktop_asobu")
  G.rect(x, y, w, h, c.white)
  local ok, title = pcall(CommandHelper.GetCommandTitle_3, "PlayMakeLove", Settings.CurrentLanguage.Value)
  title = (ok and title ~= NULL and title) or "PlayMakeLove"
  local busy = EventManager.isEventing or StatusManager.Moved.Value
  local cw = (w - 8) / 3
  for i = 1, 3 do
    local bx, by = x + 4 + (i - 1) * cw, y + h / 2 - 34
    local id = "special" .. i
    local pressed = I.touching_in(bx, by, cw, 60)
    if pressed then G.rect(bx + 4, by, cw - 8, 58, 0x4d22cf20) end
    G.draw("icon_desktop_hnakoto", bx + cw / 2 - 16, by + 2 + (pressed and 1 or 0), { fit = { 32, 32 }, alpha = busy and 0.4 or 1 })
    G.text_center(title, bx + cw / 2, by + 38, c.ink, 1, cw - 4)
    if I.focusable(id, bx, by, cw, 60) then T.focus_ring(bx + 2, by, cw - 4, 58) end
    if not busy and (I.tapped(bx, by, cw, 60) or I.activated(id)) and core.now() - last_special > 1 then
      last_special = core.now()
      if T.click_se then T.click_se() end
      EventManager:AddEvent_1(SPECIAL[win.app])
    end
  end
end

function M.draw(win, x0, y0, w0, h0)
  if SPECIAL[win.app] then return draw_special(win, x0, y0, w0, h0) end
  local cat = MAP[win.app] or "ame"
  local B = require("ui.bottom")
  -- App_KusuriDypass, App_KusuriPuron...: the window of one drug opens with it already picked
  local d = PILL[win.app]
  if d and win._pill ~= true then win._pill = true; B.debug_drug(d) end
  B.draw_category(cat, win)
end

return M
