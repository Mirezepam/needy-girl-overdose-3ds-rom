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
  for _, k in ipairs({ "dialog", "poketter", "internet", "pictures", "live", "jine", "nade", "chipget", "wristcut" }) do app_module(k) end
  -- the ChipGetCover scene component (NetaManager._chipGet / EventManager.chipget bind to it)
  core.components.ChipGetCover = app_module("chipget").cover
  app_module("endingblue").hook()
  app_module("metacover")
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
local goForced = false   -- menu opened by the GoOut window

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
  -- the GoOut window (Ame asks to go out) closes once a destination is chosen
  local go = WindowManager:find("GoOut")
  if go then WindowManager:Close(go) end
  if a == "Haishin" then
    WindowManager:NewWindow_2("NetaChoose")
    return
  end
  -- "Citas" opens the Dinder app; its Like button runs the action
  if a == "InternetDeai" then
    WindowManager:NewWindow_2("Dinder")
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
M.MENU_LABEL = MENU_LABEL
-- category icon of each act window, and the per-command icons of App_Asobu / App_Internet /
-- App_Sleep (their ShortcutPrefabs), in the same order as the original windows
local MENU_ICON = { ame = "icon_desktop_asobu", internet = "icon_desktop_internet", neru = "icon_desktop_neru",
                    okusuri = "icon_desktop_okusuri", odekake = "icon_desktop_odekake", darkness = "icon_desktop_darkness" }
local ACT_ICON = {
  ame = { EntameGame = "icon_desktop_game", PlayIchatuku = "icon_desktop_ichatsuku", PlayMakeLove = "icon_desktop_hnakoto" },
  internet = { InternetPoketter = "icon_desktop_twitter", InternetPoketterEgosa = "icon_desktop_egosearch",
               InternetYoutube = "icon_desktop_movie", Internet2ch = "icon_desktop_2ch", InternetDeai = "icon_desktop_tinder" },
  neru = { SleepToTwilight = "icon_desktop_neru_evening", SleepToNight = "icon_desktop_neru_night", SleepToTomorrow = "icon_desktop_neru_noon" },
  darkness = { Darkness = "icon_desktop_darkness" },
}
MENUS.ame = { "EntameGame", "PlayIchatuku", "PlayMakeLove" }
MENUS.internet = { "InternetPoketter", "InternetPoketterEgosa", "InternetYoutube", "Internet2ch", "InternetDeai" }

local menuScroll = {}
-- used by the PC test harness to visit every screen
function M.debug_open_menu(name) menu = name end
function M.debug_pause(v) paused = v end
-- open menu + the entry under the stylus / D-pad focus (the top screen shows the outing map)
function M.current_menu() return menu, M.menu_hover end

-- Medicine (App_Kusuri* windows): each drug with its blister / bottle art; picking one shows its
-- moderate and overdose commands, and the top screen shows its package insert (YakujoUnit)
local DRUGS = {
  { key = "dypass", art = "icon_window_daypass_none", tablet = "icon_window_daypass_tablet",
    acts = { "OkusuriDaypassModerate", "OkusuriDaypassOverdose" } },
  { key = "puron", art = "bron_base", acts = { "OkusuriPuronModerate", "OkusuriPuronOverdose" } },
  { key = "hyporon", art = "icon_window_hiporon_none", tablet = "icon_window_hiporon_capsule1",
    acts = { "OkusuriHiPuronOverdose" } },
  { key = "happa", art = "icon_window_happa", acts = { "OkusuriHappa" } },
  { key = "psyche", art = "icon_window_psyche", acts = { "OkusuriPsyche" } },
}
local drug = nil          -- selected drug
function M.debug_drug(key) for _, d in ipairs(DRUGS) do if d.key == key then drug = d end end end
M.drug_shown = nil        -- drug whose insert the top screen shows

local function drug_art(d, cx, cy, size, alpha)
  G.draw(d.art, cx, cy, { ax = 0.5, ay = 0.5, fit = { size, size }, alpha = alpha })
  if d.tablet then   -- the tablets still in the sheet (2 x 3, like the prefab)
    local s = size / 180
    for r = 0, 2 do
      for col = 0, 1 do
        G.draw(d.tablet, cx + (col == 0 and -29 or 31) * s, cy + (43 - r * 50) * -s,
          { ax = 0.5, ay = 0.5, fit = { 40 * s, 38 * s }, alpha = alpha })
      end
    end
  end
end

local function draw_pills(x, y, w, h, enabled, visible)
  local avail = {}
  for _, it in ipairs(visible) do avail[it.a] = it.s end
  M.drug_shown = drug and drug.key or nil
  if drug then
    -- the selected drug: art on the left, its commands as BaseButtons on the right
    drug_art(drug, x + 60, y + h / 2 - 6, 100, 1)
    local by = y + 10
    for _, a in ipairs(drug.acts) do
      local s = avail[a]
      if s then
        if T.button("act_" .. a, x + 126, by, w - 134, 30, cmd_title(a), { center = true, disabled = s == "Yada" or not enabled }) then
          drug = nil
          run_action(a)
          return
        end
        by = by + 36
      end
    end
    if T.button("drug_back", x + 126, y + h - 30, w - 134, 24, "◀", { center = true, flat = true }) or I.pressed(K.B) then drug = nil end
    return
  end
  local shown = {}
  for _, d in ipairs(DRUGS) do
    for _, a in ipairs(d.acts) do if avail[a] then shown[#shown + 1] = d break end end
  end
  local cw = (w - 8) / math.max(3, #shown)
  for i, d in ipairs(shown) do
    local bx = x + 4 + (i - 1) * cw
    local id = "drug_" .. d.key
    local pressed = I.touching_in(bx, y + 4, cw, h - 8)
    local foc = I.focusable(id, bx, y + 4, cw, h - 8)
    if pressed or foc then M.drug_shown = d.key; G.rect(bx + 2, y + 4, cw - 4, h - 8, 0x4d22cf18) end
    drug_art(d, bx + cw / 2, y + h / 2 - 10, math.min(cw - 8, 96), enabled and 1 or 0.4)
    local name = NgoEx.yakujo(d.key, "namae", lang())
    G.text_center(((name ~= NULL and name or d.key):gsub("%s*%(.*", ""):gsub("%s*（.*", "")), bx + cw / 2, y + h - 30, c.ink, 1, cw - 6)
    if foc then T.focus_ring(bx + 2, y + 4, cw - 4, h - 8) end
    if enabled and (I.tapped(bx, y + 4, cw, h - 8) or I.activated(id)) then
      if T.click_se then T.click_se() end
      drug = d
    end
  end
end

local function draw_menu(enabled)
  local list = MENUS[menu]
  M.visible_actions = {}
  M.menu_hover = nil
  local forced = menu == "darkness" or (menu == "odekake" and WindowManager:find("GoOut") ~= nil)
  local title = st(MENU_LABEL[menu]) or (forced and cmd_title("Darkness")) or menu
  local x, y, w, h = T.window(4, 4, 312, APP_H - 4, title)
  if forced then enabled = not StatusManager.Moved.Value
  elseif T.close("menu_close") then menu = nil; return end
  local visible = {}
  for _, a in ipairs(list) do
    local s = action_status(a)
    if s ~= "Invisible" then visible[#visible + 1] = { a = a, s = s }; M.visible_actions[a] = true end
  end
  -- TitleGroup of the original act windows: pink circle with the category icon, title, gray line
  G.rect(x, y, w, h, c.white)
  G.draw("circle", x + 4, y + 3, { w = 24, h = 24, tint = 0xefd0f0ff, blend = 1 })
  G.draw(MENU_ICON[menu] or "icon_desktop_asobu", x + 0, y - 1, { fit = { 32, 32 } })
  G.text(title, x + 38, y + 4, c.ink, 1, w - 44, 1)
  G.rect(x + 36, y + 17, w - 44, 1, 0xdfdfdfff)
  y, h = y + 28, h - 28
  if menu == "okusuri" then return draw_pills(x, y, w, h, enabled, visible) end
  -- icon grid (ShortcutPrefab: 64px icon + label) for the menus that had one on PC
  local icons = ACT_ICON[menu] and true
  if icons then
    local cols, cw, ch = 3, (w - 8) / 3, 60
    local sy = T.scroller(menuScroll, x, y, w, h, math.ceil(#visible / cols) * ch + 4)
    G.clip(x, y, w, h)
    for i, it in ipairs(visible) do
      local bx = x + 4 + ((i - 1) % cols) * cw
      local by = y + 4 + math.floor((i - 1) / cols) * ch - sy
      local id = "act_" .. it.a
      local yada = it.s == "Yada" or not enabled
      local hinted = CommandManager.isHinted and CommandManager:isHinted(it.a)
      local pressed = I.touching_in(bx, by, cw, ch - 2)
      local foc = I.focusable(id, bx, by, cw, ch - 2)
      if pressed or foc then M.menu_hover = it.a; G.rect(bx + 4, by, cw - 8, ch - 4, 0x4d22cf20) end
      if hinted then G.rect(bx + cw / 2 - 20, by, 40, 36, c.yellow) end
      G.draw(ACT_ICON[menu][it.a] or MENU_ICON[menu], bx + cw / 2 - 16, by + 2 + (pressed and 1 or 0),
        { fit = { 32, 32 }, alpha = yada and 0.4 or 1 })
      G.text_center(cmd_title(it.a), bx + cw / 2, by + 37, yada and c.inkSoft or c.ink, 1, cw - 4)
      if foc then T.focus_ring(bx + 2, by, cw - 4, ch - 4) end
      if not yada and (I.tapped(bx, by, cw, ch - 2) or I.activated(id)) then
        if T.click_se then T.click_se() end
        run_action(it.a)
      end
      if I.long_pressed(bx, by, cw, ch - 2) then CommandManager:OnActionHovered_1(it.a) end
    end
    G.unclip()
    if not I.touching and TooltipManager.current and TooltipManager.current.kind == "action" then
      if core.now() - TooltipManager.current.t > 3 then TooltipManager:Hide() end
    end
    return
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
      if I.touching_in(bx, by, bw, bh) or I.focus_id == "act_" .. it.a then M.menu_hover = it.a end
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

-- windows an event opens (Internet, Pills...) show the same category window as the desktop
-- shortcut; it closes with its x or once an action runs
function M.draw_category(cat, win)
  local prev = menu
  menu = cat
  draw_menu(true)
  local closed = menu == nil
  menu = prev ~= cat and prev or nil
  if closed and win then WindowManager:Close(win) end
end

-- 16:9 wallpaper covering the 320x220 desktop (sides cropped, no bands above / below); also
-- behind the app windows, whose area ends above the notification strip
-- WindowTweens.born / pop: a window that comes to the front grows out of its centre
local OPEN_T = 0.14
local shown = { win = nil, t = 0 }
local function open_anim(w, cx, cy, t0)
  if not t0 then
    if shown.win ~= w then shown.win, shown.t = w, core.now() end
    t0 = shown.t
  end
  local p = math.min(1, (core.now() - t0) / OPEN_T)
  if p >= 1 then return false end
  local e = 1 - (1 - p) ^ 3
  G.push_at(cx, cy, 0.25 + 0.75 * e, 0.3 + 0.7 * e)
  return true
end

local function draw_wallpaper()
  G.rect(0, 0, 320, TB_Y, c.desk)
  G.draw("FHDbg", 160, TB_Y / 2, { ax = 0.5, ay = 0.5, w = math.ceil(TB_Y * 16 / 9), h = TB_Y })
end

local function draw_desktop()
  draw_wallpaper()
  -- EventManager.SetShortcutState toggles this CanvasGroup during events, as on the PC desktop
  local shortcuts = core.ui_state("ShortCutParent")
  local enabled = TaskbarManager.interactive ~= false and not StatusManager.Moved.Value and shortcuts.interactable ~= false
  -- horror day 4: HakkyoShortCutParent replaces the desktop; every icon (and the secret one)
  -- opens the HakkyoDialog
  -- Ending_Sucide: the "liveend" icon, the only thing left on the desktop, starts the last stream
  local le = core.ui_objects.liveend
  if le and rawget(le, "_active") == true and not StatusManager.Moved.Value then
    if T.icon("desk_liveend", 4 + 2 * 66, 66, "icon_desktop_youtube", st("Shortcut_Haishin") or "Live", 1) then
      rawset(le, "_active", false)
      WindowManager:NewWindow_2("Broadcast")
    end
  end
  local hk = core.ui_state("HakkyoShortCutParent")
  local hakkyo = hk.interactable == true and (hk.alpha or 0) > 0
  if hakkyo then
    enabled = true
    if T.icon("desk_himitu", 4 + 2 * 66, 4, "icon_desktop_folder_zip", "himitu") then WindowManager:NewWindow_2("Hakkyo") end
  end
  -- the uncloseable Darkness window shows its command menu until an action runs
  if menu == "darkness" then menu = nil end
  if WindowManager:find("GoOut") and not StatusManager.Moved.Value then menu, goForced = "odekake", true
  elseif goForced then menu, goForced = nil, false end
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
  -- ShortCutParent children the story switched off (Ending_Completed's empty desktop)
  local SCENE_NAME = { live = "Live", asobu = "asobu", neru = "neru", okusuri = "okusuri", internet = "internet", odekake = "Odekake" }
  for i, d in ipairs(DESKTOP) do
    local col, row = math.floor((i - 1) / 3), (i - 1) % 3
    local x, y = 4 + col * 66, 4 + row * 62
    local so = core.ui_objects[SCENE_NAME[d.id]]
    if so and rawget(so, "_active") == false then goto next_icon end
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
      if hakkyo then WindowManager:NewWindow_2("Hakkyo")
      elseif d.open then WindowManager:NewWindow_2(d.open)
      elseif not enabled then AudioManager:PlaySeByType("SE_cancel")
      elseif d.action then run_action(d.action)
      else menu = d.menu; menuScroll.y = 0 end
    end
    ::next_icon::
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
  -- endings hide the bar (TaskBarGroup.alpha = 0)
  local tg = TaskbarManager.TaskBarGroup
  if type(tg) == "table" and tg ~= NULL and rawget(tg, "alpha") == 0 then
    G.rect(0, TB_Y, 320, 20, 0x000000ff)
    return
  end
  G.rect(0, TB_Y, 320, 20, c.paper)
  G.rect(0, TB_Y, 320, 1, c.lilac)
  local pressed = I.touching_in(1, TB_Y + 2, 68, 16)
  -- button_start at its native size (136x32 at 0.5): the Windose logo takes the first 18 px
  if not G.draw("button_start", 1, TB_Y + 2 + (pressed and 1 or 0), { scale = T.S }) then G.rect(1, TB_Y + 2, 68, 16, c.pink) end
  local sl = st("Start_Menu_Open") or "Inicio"
  local slw = G.measure(sl)
  slw = math.min(46, slw)
  G.text(sl, math.floor(44 - slw / 2), TB_Y + 5 + (pressed and 1 or 0), c.ink, 1, 48, 1)
  if I.focusable("start", 1, TB_Y + 2, 68, 16) then T.focus_ring(1, TB_Y + 2, 68, 16) end
  if I.tapped(1, TB_Y, 70, 20) or I.activated("start") then paused = true; if T.click_se then T.click_se() end end
  -- quick shortcuts (AmechanShortcut / PoketterShortcut / JineShortcut / TaskManagerShortcut)
  local QS = { { "icon_taskbar_jine", "Jine" }, { "icon_taskbar_poketter", "Poketter" }, { "icon_taskbar_taskmanager", "TaskManager" } }
  for i, q in ipairs(QS) do
    local qx = 72 + (i - 1) * 16
    local qo = q[2] == "TaskManager" and core.ui_objects.TaskManagerShortcut
    if qo and rawget(qo, "_active") == false then goto next_qs end
    if I.touching_in(qx, TB_Y + 2, 15, 16) then G.rect(qx, TB_Y + 2, 15, 16, 0x4d22cf30) end
    G.draw(q[1], qx + 1, TB_Y + 4, { fit = { 12, 12 } })
    if I.focusable("qs" .. i, qx, TB_Y + 2, 15, 16) then T.focus_ring(qx, TB_Y + 2, 15, 16) end
    if I.tapped(qx, TB_Y, 16, 20) or I.activated("qs" .. i) then WindowManager:NewWindow_2(q[2]) end
    ::next_qs::
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
  local x = 122
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
  local blue = app_module("endingblue")
  if blue.active() then blue.draw_bottom() return end
  local meta = app_module("metacover")
  if meta.active() then meta.draw_bottom() return end

  -- while the start menu or the new-idea cover is open it gets the tap; the UI below only draws
  local chipget = app_module("chipget")
  local held_tap
  if paused or chipget.active() then held_tap, I.tap = I.tap, nil end
  local f = WindowManager.focusBottom
  local mod = f and app_module(f.kind)
  local nade = app_module("nade")
  if nade.active() then
    nade.draw()
  elseif f and f.kind == "gomenu" then
    draw_desktop()
  elseif f and mod then
    draw_wallpaper()
    local anim = open_anim(f, 160, APP_H / 2)
    mod.draw(f, 0, 0, 320, APP_H)
    if anim then G.pop() end
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
    if w.kind == "dialog" then
      local anim = open_anim(w, 160, 120, w.opened or 0)
      app_module("dialog").draw(w, 0, 0, 320, 240)
      if anim then G.pop() end
    end
  end
  for _, w in ipairs(WindowManager:fxWindows()) do require("ui.fx").draw_bottom(w) end
  if chipget.active() and not paused then
    I.tap = held_tap
    chipget.draw()
  end
  if paused then
    I.tap = held_tap
    if pause.draw(function() paused = false end) then paused = false end
  end
  local fake = CursorManager.fake
  if fake and fake.visible and not G.draw("cursor", fake.x, fake.y) then G.rect(fake.x, fake.y, 4, 6, c.white) end
end

return M
