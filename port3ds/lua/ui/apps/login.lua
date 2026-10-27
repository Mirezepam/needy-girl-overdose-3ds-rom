-- Stream account login (Login.cs). Like the console version the password types itself; it can
-- also be typed with the 3DS keyboard. A correct password enables the login button.
local core = require("runtime.core")
local G = require("runtime.gfx")
local I = require("runtime.input")
local T = require("ui.theme")
local c = T.c

local M = { icon = "icon_desktop_youtube" }
local PASS = "angelkawaii2"
local state = { text = "", t0 = nil }

function M.draw(win, x0, y0, w0, h0)
  local x, y, w, h = T.window(x0 + 10, y0 + 10, w0 - 20, h0 - 20, T.st("Window_Login", "Login"), "icon_desktop_youtube")
  if win.closeable and T.close("login_close") then
    WindowManager:Close(win) return
  end
  if not state.t0 then state.t0 = core.now() end
  -- auto-typing after a short pause (ConsoleInput in the original)
  local typed = state.text
  if typed == "" then
    local n = math.floor(math.max(0, core.now() - state.t0 - 1.1) / 0.25)
    typed = PASS:sub(1, math.min(#PASS, n))
  end
  -- App_Login: purple background (#a489e4) with the login art, the password field in the middle
  -- ("password" placeholder) and the login BaseButton below
  G.rect(x, y, w, h, 0xa489e4ff)
  G.draw("login", x + w / 2, y + h / 2, { ax = 0.5, ay = 0.5, fit = { w - 8, h - 8 } })
  local fx, fy, fw = x + w / 2 - 66, y + h / 2 - 22, 132
  if not G.draw9("InputFieldBackground", fx, fy, fw, 20, 0.5) then G.rect(fx, fy, fw, 20, c.white) end
  if typed == "" then G.text_center("password", fx + fw / 2, fy + 4, 0x4d22cf80)
  else G.text_center(typed, fx + fw / 2, fy + 4, c.ink) end
  if I.focusable("login_field", fx, fy, fw, 20) then T.focus_ring(fx, fy, fw, 20) end
  if I.tapped(fx, fy, fw, 20) or I.activated("login_field") then
    core.keyboard("password", 20, function(s) if s then state.text = s end end)
  end
  local ok = typed == PASS or typed == "angelikawaii2"
  if T.button("login_go", x + w / 2 - 50, fy + 30, 100, 20, "login", { center = true, disabled = not ok }) then
    state.text, state.t0 = "", nil
    EventManager:AddEvent_1("Scenario_loop1_day0_night_AfterLogin")
  end
end

return M
