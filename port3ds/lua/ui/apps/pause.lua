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

-- Control panel (ControllPanelView): BGM and SE sliders 0-100 applied while dragging (SE_per as
-- the SE one moves), the language toggles, OK (saves volumes + language) and Cancel / x / B
-- (back to the volumes it opened with). Resolution and vibration are PC / console only.
local cp
local LANG_TOGGLES = { { "JP", "日本語" }, { "EN", "English" }, { "SP", "Español" } }
local LANG_FILE = { JP = "ja", EN = "en", SP = "es" }

-- a Slider: drag with the stylus, or D-pad left / right when focused
local function slider(id, x, y, w, v)
  G.rect(x, y + 7, w, 4, 0xcdebfcff)
  G.rect(x, y + 7, w * v / 100, 4, c.sky)
  local kx = x + w * v / 100
  G.rect(kx - 4, y + 2, 8, 14, c.white)
  G.frame_rect(kx - 4, y + 2, 8, 14, c.ink, 1)
  local foc = I.focusable(id, x - 4, y, w + 8, 18)
  if foc then T.focus_ring(x - 4, y, w + 8, 18) end
  if I.touching_in(x - 6, y - 4, w + 12, 26) then v = (I.tx - x) / w * 100
  elseif foc and (I.isheld(I.KEY.DLEFT) or I.isheld(I.KEY.DRIGHT)) then
    cp.rep = (cp.rep or 0) + 1
    if cp.rep == 1 or cp.rep > 20 and cp.rep % 3 == 0 then v = v + (I.isheld(I.KEY.DRIGHT) and 1 or -1) end
  elseif foc then cp.rep = 0 end
  return math.max(0, math.min(100, math.floor(v + 0.5)))
end

local function reset_volume()
  AudioManager:ChangeVolume("BGM", cp.bgm0 / 100)
  AudioManager:ChangeSeVolume(cp.se0 / 100)
end

local function control_panel(on_close)
  if not cp then
    local b, s0 = math.floor((Settings.BgmVolume or 0.6) * 100 + 0.5), math.floor((Settings.SeVolume or 0.8) * 100 + 0.5)
    cp = { bgm = b, se = s0, bgm0 = b, se0 = s0, lang = Settings.CurrentLanguage.Value, seT = -10 }
  end
  local function close()
    panel, cp = false, nil
    if on_close then on_close() end
  end
  local x, y, w, h = T.window(10, 8, 300, 206, st("Start_Menu_Config", "Panel de control"), "icon_gear")
  if T.close("cp_close") or I.pressed(I.KEY.B) then reset_volume(); close() return end
  G.rect(x, y, w, h, c.paper)
  local yy = y + 8
  G.text(st("Config_BGM", "BGM"), x + 8, yy + 3, c.ink, 1, 70, 1)
  local nb = slider("cp_bgm", x + 84, yy, 160, cp.bgm)
  G.text(tostring(nb), x + 254, yy + 3, c.ink)
  if nb ~= cp.bgm then cp.bgm = nb; AudioManager:ChangeVolume("BGM", nb / 100) end
  yy = yy + 30
  G.text(st("Config_SE", "SE"), x + 8, yy + 3, c.ink, 1, 70, 1)
  local ns = slider("cp_se", x + 84, yy, 160, cp.se)
  G.text(tostring(ns), x + 254, yy + 3, c.ink)
  if ns ~= cp.se then
    cp.se = ns
    AudioManager:ChangeSeVolume(ns / 100)
    if core.now() - cp.seT > 1.6 then cp.seT = core.now(); AudioManager:PlaySeByType("SE_per") end
  end
  yy = yy + 34
  G.text(st("Config_Language", "Language"), x + 8, yy, c.ink, 1, w - 16, 1)
  yy = yy + 16
  for i, l in ipairs(LANG_TOGGLES) do
    local bx = x + 8 + (i - 1) * 94
    if T.button("cp_lang" .. i, bx, yy, 88, 22, l[2], { center = true, fill = cp.lang == l[1] and c.yellow or nil }) then cp.lang = l[1] end
  end
  local by = y + h - 30
  if T.button("cp_ok", x + w / 2 - 116, by, 110, 22, st("Dialog_OK", "OK"), { center = true }) then
    if cp.lang ~= Settings.CurrentLanguage.Value and LANG_FILE[cp.lang] then
      require("runtime.data").load(LANG_FILE[cp.lang])
      Settings:ChangeLanguage(cp.lang)
      sys.write("sdmc:/3ds/needy3ds/save/port_lang.txt", LANG_FILE[cp.lang])
    end
    Settings.BgmVolume, Settings.SeVolume = cp.bgm / 100, cp.se / 100
    spawn(function() Settings:Save() end)
    close()
    return
  end
  if T.button("cp_cancel", x + w / 2 + 6, by, 110, 22, st("Dialog_Cancell", "Cancel"), { center = true }) then
    reset_volume(); close()
  end
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

M.control_panel = control_panel
return M
