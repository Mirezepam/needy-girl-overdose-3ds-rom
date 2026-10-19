-- Start menu (START / Start button), like the original MainPanel/StartMenuParent: the start_menu
-- art (gradient sidebar) above the Start button with My pictures, Control panel and Restart, plus
-- Shut down (the 3DS has no window close button to quit with).
local core = require("runtime.core")
local G = require("runtime.gfx")
local I = require("runtime.input")
local T = require("ui.theme")
local c = T.c

local M = {}
local panel = false

local function lang() return Settings.CurrentLanguage.Value end
local function st(id, fallback)
  local ok, s = pcall(NgoEx.SystemTextFromType, id, lang())
  return (ok and type(s) == "string" and s ~= "") and s or fallback
end

-- Control panel (ControllPanel button): volumes, stream speed, text skip, endings seen
local function control_panel()
  local x, y, w, h = T.window(10, 8, 300, 206, st("Start_Menu_Config", "Panel de control"), "icon_gear")
  if T.close("cp_close") or I.pressed(I.KEY.B) then panel = false return end
  G.rect(x, y, w, h, c.paper)
  local yy = y + 6
  local bgm = math.floor((AudioManager.bgmVolume or 0.8) * 10 + 0.5)
  G.text("Música: " .. bgm, x + 8, yy + 6, c.ink)
  if T.button("p_bgm-", x + 150, yy, 40, 22, "-", { center = true }) then AudioManager:ChangeMasterVolume(math.max(0, (bgm - 1) / 10)) end
  if T.button("p_bgm+", x + 196, yy, 40, 22, "+", { center = true }) then AudioManager:ChangeMasterVolume(math.min(1, (bgm + 1) / 10)) end
  yy = yy + 28
  local se = math.floor((AudioManager.seVolume or 0.9) * 10 + 0.5)
  G.text("Efectos: " .. se, x + 8, yy + 6, c.ink)
  if T.button("p_se-", x + 150, yy, 40, 22, "-", { center = true }) then AudioManager.seVolume = math.max(0, (se - 1) / 10) end
  if T.button("p_se+", x + 196, yy, 40, 22, "+", { center = true }) then AudioManager.seVolume = math.min(1, (se + 1) / 10) end
  yy = yy + 28
  local sp = Settings.haishinSpeed or 0
  G.text("Velocidad del directo: " .. (sp + 1), x + 8, yy + 6, c.ink)
  if T.button("p_speed", x + 196, yy, 86, 22, "Cambiar", { center = true }) then
    Settings.haishinSpeed = (sp + 1) % 3
    spawn(function() Settings:Save() end)
  end
  yy = yy + 28
  G.text("Saltar texto (SELECT): " .. (core.fast and "Sí" or "No"), x + 8, yy + 6, c.ink)
  if T.button("p_fast", x + 196, yy, 86, 22, "Cambiar", { center = true }) then core.fast = not core.fast end
  yy = yy + 30
  local seen = Settings.mitaEnd and Settings.mitaEnd:Distinct().Count or 0
  G.text("Finales vistos: " .. seen .. " / 26", x + 8, yy + 4, c.lilacDark)
end

-- returns true when the menu should close
function M.draw(close)
  if panel then control_panel() return false end
  local items = {
    { st("Start_Menu_MyPicture", "Mis imágenes"), function() WindowManager:NewWindow_2("MyPicture"); close() end },
    { st("Start_Menu_Config", "Panel de control"), function() panel = true end },
    { st("Start_Menu_Restart", "Reiniciar"), function() WindowManager:NewWindow_2("RebootDialog"); close() end },
    { st("Start_Menu_Shutdown", "Apagar"), function() WindowManager:NewWindow_2("ShutDownDialog"); close() end },
  }
  local mw, mh = 108, 20 * #items + 12
  local mx, my = 1, 220 - mh
  if not G.draw9("start_menu", mx, my, mw, mh, 0.5) then T.panel(mx, my, mw, mh) end
  for i, it in ipairs(items) do
    local iy = my + 6 + (i - 1) * 20
    local id = "sm" .. i
    local hover = I.touching_in(mx + 7, iy, 100, 20) or I.focusable(id, mx + 7, iy, 100, 20)
    if hover and not G.draw("button_startmenu_selected", mx + 7, iy, { w = 100, h = 20 }) then
      G.rect(mx + 7, iy, 100, 20, c.ink)
    end
    G.text(it[1], mx + 12, iy + 4, hover and c.white or c.ink, 1, 92, 1)
    if I.tapped(mx + 7, iy, 100, 20) or I.activated(id) then it[2]() return false end
  end
  -- tap outside or B closes the menu
  if I.pressed(I.KEY.B) then return true end
  if I.tap and not I.inside(I.tap, mx, my, mw, mh) then I.tap = nil return true end
  return false
end

return M
