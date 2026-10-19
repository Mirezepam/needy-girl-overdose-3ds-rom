-- Stream account login (Login.cs). Like the console version the password types itself; it can
-- also be typed with the 3DS keyboard. A correct password enables the login button.
local core = require("runtime.core")
local G = require("runtime.gfx")
local T = require("ui.theme")
local c = T.c

local M = { icon = "icon_desktop_youtube" }
local PASS = "angelkawaii2"
local state = { text = "", t0 = nil }

function M.draw(win, x0, y0, w0, h0)
  local x, y, w, h = T.window(x0 + 20, y0 + 20, w0 - 40, h0 - 40, "Login", "icon_desktop_youtube")
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
  G.text("Contraseña", x + 10, y + 10, c.inkSoft)
  if T.button("login_field", x + 10, y + 24, w - 20, 26, string.rep("*", #typed), { fill = c.white }) then
    local s = sys.keyboard("Contraseña", "", 20)
    if s then state.text = s end
  end
  local ok = typed == PASS or typed == "angelikawaii2"
  if T.button("login_go", x + 40, y + 70, w - 80, 34, "Iniciar sesión", { center = true, fill = ok and c.pink or nil, disabled = not ok }) then
    state.text, state.t0 = "", nil
    EventManager:AddEvent_1("Scenario_loop1_day0_night_AfterLogin")
  end
end

return M
