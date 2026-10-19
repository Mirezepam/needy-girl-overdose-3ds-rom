-- BOTTOM SCREEN (320x240, touch): the Windose OS. Desktop icons, one app at a time,
-- taskbar, notification strip, modal dialogs and the pause menu (docs/PANTALLAS.md).
local core = require("runtime.core")
local G = require("runtime.gfx")
local I = require("runtime.input")
local T = require("ui.theme")
local K = I.KEY
local c = T.c

local M = {}
local apps = {}
local paused = false
local pause = nil
local APP_H = 202          -- content area height (above notification strip + taskbar)
local TB_Y = 220

local function app_module(kind)
  if apps[kind] == nil then
    local ok, mod = pcall(require, "ui.apps." .. kind)
    if not ok then LOG("app module", kind, mod) end
    apps[kind] = ok and mod or false
  end
  return apps[kind] or nil
end
M.app_module = app_module

function M.init()
  pause = require("ui.apps.pause")
  -- modules that register views the game code calls right after opening a window
  for _, k in ipairs({ "dialog", "poketter", "internet", "pictures", "live", "jine", "nade" }) do app_module(k) end
end

local function lang() return Settings.CurrentLanguage.Value end
local function cmd_title(a)
  local ok, t = pcall(CommandHelper.GetCommandTitle_3, a, lang())
  if not ok then t = nil end
  if t and t ~= NULL and t ~= "" then return t end
  return a
end

local function st(id)
  local ok, s = pcall(NgoEx.SystemTextFromType, id, lang())
  return (ok and type(s) == "string" and s ~= "") and s or nil
end

-- desktop shortcuts in the original order (MainPanel/ShortCutParent): Live, asobu, neru, okusuri,
-- internet, Odekake. JINE / Poketter / Task manager live in the taskbar like on PC.
local DESKTOP = {
  { id = "live", icon = "icon_desktop_youtube", label = "Shortcut_Haishin", action = "Haishin" },
  { id = "asobu", icon = "icon_desktop_asobu", label = "Shortcut_Play", menu = "ame" },
  { id = "neru", icon = "icon_desktop_neru", label = "Window_Sleep", menu = "neru" },
  { id = "okusuri", icon = "icon_desktop_okusuri", label = "Shortcut_Drug", menu = "okusuri" },
  { id = "internet", icon = "icon_desktop_internet", label = "Window_Internet", menu = "internet" },
  { id = "odekake", icon = "icon_desktop_odekake", label = "Shortcut_Odekake", menu = "odekake" },
}
local MENU_LABEL = { darkness = "Window_Darkness", internet = "Window_Internet", ame = "Shortcut_Play", okusuri = "Shortcut_Drug", odekake = "Shortcut_Odekake", neru = "Window_Sleep" }

function M.update(dt)
  if not StatusManager.statuses then return end
  if I.pressed(K.START) then paused = not paused end
  -- SELECT toggles "skip text" (inside a stream SELECT skips the broadcast instead)
  local f0 = WindowManager.focusBottom
  if I.pressed(K.SELECT) and not (f0 and f0.kind == "live") then core.fast = not core.fast end
  -- events make the whole screen clickable through EventManager.cover (skip train rides, etc.)
  local cover = EventManager.cover
  if type(cover) == "table" and cover ~= NULL and cover.interactable == true and (I.tap_down or I.pressed(K.A)) then
    core.fire_pointer(cover, "down")
  end
  if paused then return end   -- (start menu open)
  local wm = WindowManager
  if I.pressed(K.Y) then wm:NewWindow_2("Jine") end
  if I.pressed(K.X) then wm:NewWindow_2("Poketter") end
  local f = wm.focusBottom
  if I.pressed(K.B) and f and f.closeable and not rawget(f, "modal") then
    local mod = app_module(f.kind)
    if not (mod and mod.back and mod.back(f)) then wm:Close(f) end
  end
  -- L/R cycle through open bottom apps (the stream uses R for speed instead)
  if not (f and f.kind == "live") and (I.pressed(K.L) or I.pressed(K.R)) then
    local list = {}
    for _, w in EACH(wm.windows) do if w.screen == "bottom" or w.screen == "both" then list[#list + 1] = w end end
    if #list > 0 then
      local idx = 0
      for i, w in ipairs(list) do if w == f then idx = i end end
      idx = idx + (I.pressed(K.R) and 1 or -1)
      if idx < 1 then idx = #list elseif idx > #list then idx = 1 end
      wm:Touched(list[idx])
    end
  end
  for _, mod in pairs(apps) do if mod and mod.update then mod.update(dt) end end
end

-- ------------------------------------------------------------------ desktop
local menu = nil   -- open action category

local function action_status(a)
  local st = CommandManager.commandStatus and CommandManager.commandStatus.Value
  local s = st and st ~= NULL and st:__idx(a)
  if a == "SleepToTwilight" and StatusManager:GetStatus("DayPart") > 0 then return "Invisible" end
  if a == "SleepToNight" and StatusManager:GetStatus("DayPart") > 1 then return "Invisible" end
  return s or "Executable"
end

local function run_action(a)
  if StatusManager.Moved.Value then return end
  menu = nil
  if a == "Haishin" then
    WindowManager:NewWindow_2("NetaChoose")
    return
  end
  CommandManager:CommandAction_2(a)
end

local MENUS = {
  internet = { "InternetYoutube", "InternetPoketter", "InternetPoketterEgosa", "Internet2ch", "InternetDeai" },
  ame = { "PlayIchatuku", "PlayMakeLove", "EntameGame" },
  okusuri = { "OkusuriDaypassModerate", "OkusuriDaypassOverdose", "OkusuriPuronModerate", "OkusuriPuronOverdose",
              "OkusuriHiPuronOverdose", "OkusuriHappa", "OkusuriPsyche" },
  neru = { "SleepToTwilight", "SleepToNight", "SleepToTomorrow" },
  odekake = { "OdekakeNakano", "OdekakeHarajuku", "OdekakeAkihabara", "OdekakeShibuya", "OdekakeIkebukuro", "OdekakeUeno",
              "OdekakeJinbocho", "OdekakeShimokitazawa", "OdekakeKichijoji", "OdekakeGisneyland", "OdekakeHikarigaokaPark",
              "OdekakeAsakusa", "OdekakeShinjuku", "OdekakeToyosu", "OdekakeOdaiba", "OdekakeIchigaya",
              "OdekakeZikka", "OdekakeHospital", "OdekakeGinga" },
  -- the Darkness window (Status_Stress1_Day): "Colapso" -> DarknessS1 (cut) / DarknessS2 (berserk)
  darkness = { "Darkness" },
}
M.MENUS = MENUS

local menuScroll = {}
-- used by the PC test harness to visit every screen
function M.debug_open_menu(name) menu = name end
function M.debug_pause(v) paused = v end
local function draw_menu(enabled)
  local list = MENUS[menu]
  local forced = menu == "darkness"
  local title = st(MENU_LABEL[menu]) or (forced and cmd_title("Darkness")) or menu
  local x, y, w, h = T.window(4, 4, 312, APP_H - 4, title)
  if forced then enabled = not StatusManager.Moved.Value
  elseif T.close("menu_close") then menu = nil; return end
  local visible = {}
  for _, a in ipairs(list) do
    local s = action_status(a)
    if s ~= "Invisible" then visible[#visible + 1] = { a = a, s = s } end
  end
  local cols = menu == "odekake" and 2 or 1
  local bh = 30
  local rows = math.ceil(#visible / cols)
  local sy = T.scroller(menuScroll, x, y, w, h, rows * (bh + 4) + 4)
  G.clip(x, y, w, h)
  for i, it in ipairs(visible) do
    local col = (i - 1) % cols
    local row = math.floor((i - 1) / cols)
    local bw = (w - 8 - (cols - 1) * 4) / cols
    local bx, by = x + 4 + col * (bw + 4), y + 4 + row * (bh + 4) - sy
    if by > y - bh and by < y + h then
      local yada = it.s == "Yada"
      local hinted = CommandManager.isHinted and CommandManager:isHinted(it.a)
      if T.button("act_" .. it.a, bx, by, bw, bh, cmd_title(it.a), { disabled = yada or not enabled, fill = hinted and c.yellow or nil, maxLines = 2 }) then
        run_action(it.a)
      end
      -- long press: tooltip with the command description on the TOP screen
      if I.long_pressed(bx, by, bw, bh) then CommandManager:OnActionHovered_1(it.a) end
    end
  end
  G.unclip()
  if not I.touching and TooltipManager.current and TooltipManager.current.kind == "action" then
    if core.now() - TooltipManager.current.t > 3 then TooltipManager:Hide() end
  end
end

local function draw_desktop()
  G.rect(0, 0, 320, TB_Y, c.desk)
  G.draw("FHDbg", 160, 110, { ax = 0.5, ay = 0.5, fit = { 320, 220 } })
  -- EventManager.SetShortcutState toggles this CanvasGroup during events, as on the PC desktop
  local shortcuts = core.ui_state("ShortCutParent")
  local enabled = TaskbarManager.interactive ~= false and not StatusManager.Moved.Value and shortcuts.interactable ~= false
  -- the uncloseable Darkness window shows its command menu until an action runs
  local dark = WindowManager:find("Darkness")
  if dark and not StatusManager.Moved.Value then menu = "darkness" elseif menu == "darkness" then menu = nil end
  if menu then draw_menu(enabled) return end
  -- diary shortcuts the story unlocks (EventManager.PsycheNikkiN / LoveNikkiN SetActive(true))
  local dx, dy = 140, 4
  local SHORTCUTS = {
    { "EventManager.PsycheNikki1", "PsycheNikki1" }, { "EventManager.PsycheNikki2", "PsycheNikki2" },
    { "EventManager.PsycheNikki3", "PsycheNikki3" }, { "EventManager.PsycheNikki4", "PsycheNikki4" },
    { "EventManager.LoveNikki1", "Event_Diary004" }, { "EventManager.LoveNikki2", "Event_Diary003" },
    { "EventManager.LoveNikki3", "Event_Diary002" }, { "EventManager.LoveNikki4", "Event_Diary001" },
  }
  for i, sc in ipairs(SHORTCUTS) do
    local obj = core.ui_objects[sc[1]]
    if obj and rawget(obj, "_active") == true then
      if T.icon("desk_doc" .. i, dx, dy, "icon_desktop_text", st("Shortcut_nikki") or "Diario") then
        WindowManager:NewWindow_2(sc[2])
      end
      dx = dx + 64
      if dx > 270 then dx, dy = 140, dy + 62 end
    end
  end
  -- the stream account login appears once the story asks for it
  local login = core.ui_state("LoginShortCut")
  if login.interactable == true and (login.alpha or 0) > 0 then
    if T.icon("desk_login", 12, 140, "icon_desktop_youtube", "Login", 1) then WindowManager:NewWindow_2("Login") end
  end
  for i, d in ipairs(DESKTOP) do
    local col, row = math.floor((i - 1) / 3), (i - 1) % 3
    local x, y = 4 + col * 66, 4 + row * 62
    local label = st(d.label) or d.id
    local badge = 0
    if d.open then
      for _, n in ipairs(NotificationManager.items) do if n.app == d.open then badge = badge + 1 end end
    end
    local hinted = d.action and CommandManager.isHinted and CommandManager:isHinted(d.action)
    if hinted then G.rect(x + 12, y, 40, 36, c.yellow) end
    local icon = d.icon
    if d.id == "neru" then icon = "icon_desktop_neru_" .. (({ [0] = "noon", "evening", "night" })[StatusManager:GetStatus("DayPart")] or "night") end
    if T.icon("desk_" .. d.id, x, y, icon, label, badge) then
      if d.open then WindowManager:NewWindow_2(d.open)
      elseif not enabled then AudioManager:PlaySeByType("SE_cancel")
      elseif d.action then run_action(d.action)
      else menu = d.menu; menuScroll.y = 0 end
    end
  end
  if not enabled then
    G.text_center("…", 160, 150, c.white)
  end
end

-- ------------------------------------------------------------------ notifications + taskbar
-- Notification prefab: tuuti card (light blue, ink shadow) with the app icon and one or two lines,
-- sliding in from the right above the taskbar; tap opens it
local NOTIF_ICON = { Jine = "icon_taskbar_jine", Poketter = "icon_taskbar_poketter", Webcam = "icon_jine_ame" }
local function draw_notifications()
  local items = NotificationManager.items
  if not items or #items == 0 then return end
  local n = items[#items]
  local w, h = 210, 30
  local slide = math.min(1, (core.now() - (n.born or 0)) / 0.25)
  local x = 320 - (w + 4) * (1 - (1 - slide) ^ 2)
  local y = TB_Y - h - 2
  local timey = n.style == "time"
  if not G.draw9("tuuti", x, y, w, h, 0.5) then G.rect(x, y, w, h, 0xcdebfcff) end
  if timey then G.rect(x, y, w - 2, h - 2, math.floor((math.sin(core.now() * 6) * 0.5 + 0.5) * 0x50) + 0xff9fd600) end
  local icon = timey and "icon_watch_noon" or (NOTIF_ICON[n.app] or "icon_taskbar_taskmanager")
  G.draw(icon, x + 4, y + (h - 2 - 16) / 2, { fit = { 16, 16 } })
  local label = n.text:gsub("\n", " ")
  G.text(label, x + 24, y + 3, c.ink, 1, w - 30 - (#items > 1 and 18 or 0), 2)
  if #items > 1 then
    G.rect(x + w - 20, y + 2, 16, 11, c.red)
    G.text_center(tostring(#items), x + w - 12, y + 2, c.white)
  end
  if I.focusable("notif", x, y, w, h) then T.focus_ring(x, y, w, h) end
  if I.tapped(x, y, w, h) or I.activated("notif") then
    if T.click_se then T.click_se() end
    NotificationManager:click(n)
  end
end

-- MainPanel/Taskbar: StartButton (button_start), JINE / Poketter / Task manager shortcuts,
-- open windows, and the DayButton (button_day) with the day and time of day on the right
local function draw_taskbar()
  G.rect(0, TB_Y, 320, 20, c.paper)
  G.rect(0, TB_Y, 320, 1, c.lilac)
  local pressed = I.touching_in(1, TB_Y + 2, 54, 16)
  if not G.draw("button_start", 1, TB_Y + 2 + (pressed and 1 or 0), { w = 54, h = 16 }) then G.rect(1, TB_Y + 2, 54, 16, c.pink) end
  G.text_center(st("Start_Menu_Open") or "Inicio", 34, TB_Y + 5 + (pressed and 1 or 0), c.ink)
  if I.focusable("start", 1, TB_Y + 2, 54, 16) then T.focus_ring(1, TB_Y + 2, 54, 16) end
  if I.tapped(1, TB_Y, 56, 20) or I.activated("start") then paused = true; if T.click_se then T.click_se() end end
  -- quick shortcuts (AmechanShortcut / PoketterShortcut / JineShortcut / TaskManagerShortcut)
  local QS = { { "icon_taskbar_jine", "Jine" }, { "icon_taskbar_poketter", "Poketter" }, { "icon_taskbar_taskmanager", "TaskManager" } }
  for i, q in ipairs(QS) do
    local qx = 58 + (i - 1) * 16
    if I.touching_in(qx, TB_Y + 2, 15, 16) then G.rect(qx, TB_Y + 2, 15, 16, 0x4d22cf30) end
    G.draw(q[1], qx + 1, TB_Y + 4, { fit = { 12, 12 } })
    if I.focusable("qs" .. i, qx, TB_Y + 2, 15, 16) then T.focus_ring(qx, TB_Y + 2, 15, 16) end
    if I.tapped(qx, TB_Y, 16, 20) or I.activated("qs" .. i) then WindowManager:NewWindow_2(q[2]) end
  end
  -- day button
  local day = StatusManager:GetStatus("DayIndex")
  local dp = StatusManager:GetStatus("DayPart")
  if not G.draw("button_day", 254, TB_Y + 2, { w = 64, h = 16 }) then G.rect(254, TB_Y + 2, 64, 16, c.white) end
  G.draw("icon_watch_" .. (({ [0] = "noon", "evening", "night" })[dp] or "night"), 257, TB_Y + 4, { fit = { 12, 12 } })
  G.text((st("Day_Live") or "DÍA") .. " " .. day, 272, TB_Y + 4, c.ink)
  -- skip text toggle
  if T.button("skip", 230, TB_Y + 2, 22, 16, ">>", { center = true, flat = true, fill = core.fast and c.yellow or c.paper2 }) then
    core.fast = not core.fast
  end
  local x = 108
  for _, w in EACH(WindowManager.windows) do
    if (w.screen == "bottom" or w.screen == "both") and x < 205 then
      local active = WindowManager.focusBottom == w
      local mod = app_module(w.kind)
      local icon = mod and mod.icon or "windowbase_icon"
      if T.button("tb_" .. w.app, x, TB_Y + 2, 24, 16, "", { icon = icon, iconSize = 12, iconX = 6, flat = true, fill = active and c.white or 0xe6dcf5ff }) then
        if active and w.closeable then WindowManager:MinifyApp(w.app) else WindowManager:Touched(w) end
      end
      x = x + 25
    end
  end
end

-- ------------------------------------------------------------------ frame
function M.draw()
  if not StatusManager.statuses then G.rect(0, 0, 320, 240, 0x000000ff) return end

  -- while the start menu is open it gets the tap; the UI below only draws
  local held_tap
  if paused then held_tap, I.tap = I.tap, nil end
  local f = WindowManager.focusBottom
  local mod = f and app_module(f.kind)
  local nade = app_module("nade")
  if nade.active() then
    nade.draw()
  elseif f and mod then
    G.rect(0, 0, 320, TB_Y, c.desk)
    mod.draw(f, 0, 0, 320, APP_H)
  elseif f then
    local x, y = T.window(4, 4, 312, APP_H - 4, f.app)
    G.text("(" .. f.app .. ")", x + 4, y + 4, c.inkSoft)
    if f.closeable and T.close("close_generic") then WindowManager:Close(f) end
  else
    draw_desktop()
  end
  draw_notifications()
  draw_taskbar()
  -- modal dialogs and full-screen effects always on top
  for _, w in EACH(WindowManager.windows) do
    if w.kind == "dialog" then app_module("dialog").draw(w, 0, 0, 320, 240) end
  end
  for _, w in ipairs(WindowManager:fxWindows()) do require("ui.fx").draw_bottom(w) end
  if paused then
    I.tap = held_tap
    if pause.draw(function() paused = false end) then paused = false end
  end
  local fake = CursorManager.fake
  if fake and fake.visible and not G.draw("cursor", fake.x, fake.y) then G.rect(fake.x, fake.y, 4, 6, c.white) end
end

return M
