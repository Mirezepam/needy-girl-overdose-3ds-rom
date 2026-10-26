-- PC test harness: runs the 3DS Lua runtime headless with a stub `sys` module and a bot that
-- plays (JINE options, time-passing notifications, streams, actions). Prints what happens.
-- usage: lua54 pc_harness.lua <port3ds dir> [frames] [days]
local PORT = arg[1] or "."
local MAX_FRAMES = tonumber(arg[2] or "60000")
local MAX_DAYS = tonumber(arg[3] or "5")
local DATA = PORT .. "/build_data/needy3ds/"
local SAVE = PORT .. "/build_data/pc_save/"
os.execute('mkdir "' .. SAVE:gsub("/", "\\") .. '" 2>nul')

package.path = PORT .. "/lua/?.lua;" .. DATA .. "?.lua;" .. package.path

local function map(p)
  p = p:gsub("^sdmc:/3ds/needy3ds/save/", SAVE)
  p = p:gsub("^sdmc:/3ds/needy3ds/", DATA)
  return p
end

local now_ms = 0
local texid = 0
local TEXSIZE = {}   -- local: the game runtime intercepts unknown globals
-- ---------------------------------------------------------------- font metrics identical to source/gfx.c
local FONT = { glyphs = {} }
do
  local f = assert(io.open(DATA .. "font/main.bin", "rb"))
  local b = f:read("a"); f:close()
  FONT.cw, FONT.ch, FONT.n = string.unpack("<I2I2I4", b, 5)
  for i = 0, FONT.n - 1 do
    local cp, x, y, w, adv = string.unpack("<I4I2I2BB", b, 13 + i * 10)
    FONT.glyphs[cp] = { x = x, y = y, w = w, adv = adv }
  end
end
local function lh() return FONT.ch - 4 end
local function is_wide(cp) return cp >= 0x2e80 end
local function adv(cp)
  if cp == 32 then return FONT.cw / 2.5 end
  local g = FONT.glyphs[cp]
  return g and g.adv or FONT.cw / 2
end
local function codes(s)
  local t = {}
  for _, cp in utf8.codes(s, true) do t[#t + 1] = cp end
  return t
end
local REC = nil         -- current recording: list of commands for the screen being drawn
local function font_layout(s, x, y, color, scale, wrap, maxLines, emit)
  scale = scale or 1; wrap = wrap or 0; maxLines = maxLines or 0
  local ok, cps = pcall(codes, s)
  if not ok then return 0, 0 end
  local cx, cy, maxW, line = x, y, 0, 1
  local i = 1
  local alpha = (color & 0xff) / 255
  while i <= #cps do
    local cp = cps[i]
    if cp == 10 then
      i = i + 1
      if cx - x > maxW then maxW = cx - x end
      if maxLines > 0 and line >= maxLines then break end
      cx, cy, line = x, cy + lh() * scale, line + 1
    else
      if wrap > 0 and cp ~= 32 then
        local ww, j = 0, i
        while j <= #cps and cps[j] ~= 32 and cps[j] ~= 10 do
          if is_wide(cps[j]) and ww > 0 then break end
          ww = ww + adv(cps[j]) * scale
          if is_wide(cps[j]) then break end
          j = j + 1
        end
        if cx > x and cx + ww > x + wrap then
          if cx - x > maxW then maxW = cx - x end
          if maxLines > 0 and line >= maxLines then break end
          cx, cy, line = x, cy + lh() * scale, line + 1
        end
      end
      i = i + 1
      if not (cp == 32 and cx == x and line > 1) then
        local g = FONT.glyphs[cp]
        if g and emit and cp ~= 32 then
          emit[#emit + 1] = { "draw", "font", g.x, g.y, FONT.cw, FONT.ch, cx, cy - 2 * scale, scale, scale, alpha, color, 1.0 }
        end
        cx = cx + adv(cp) * scale
      end
    end
  end
  if cx - x > maxW then maxW = cx - x end
  return (cy - y) + lh() * scale, maxW
end
-- NGO_LINT=1: report texts that leave the screen, invisible texts and Japanese shown outside
-- Japanese (unique, with the screen and a short excerpt)
LINT = nil
if os.getenv("NGO_LINT") == "1" then
  local seen = {}
  LINT = function(s, x, y, w, h, c, wrap, maxLines)
    if s == "" then return end
    local G = package.loaded["runtime.gfx"]
    local scr = G and G.screen == 0 and "top" or "bottom"
    local sw = scr == "top" and 400 or 320
    local issues = {}
    if x + w > sw + 1 then issues[#issues + 1] = string.format("overflow-right %d>%d", math.floor(x + w), sw) end
    if x < -1 then issues[#issues + 1] = "overflow-left" end
    if y + h > 241 then issues[#issues + 1] = "overflow-bottom" end
    if c and (c & 0xff) == 0 then issues[#issues + 1] = "transparent" end
    if (maxLines or 0) > 0 and (wrap or 0) > 0 then
      local fh = font_layout(s, 0, 0, 0xffffffff, 1, wrap, 0, nil)
      if fh > h + 1 then issues[#issues + 1] = "truncated" end
    end
    local lang = Settings and Settings.CurrentLanguage and Settings.CurrentLanguage.Value
    if lang and lang ~= "JP" and s:find("[�-�]") then
      -- hiragana/katakana/kanji (U+3040..U+9FFF) outside Japanese
      local ok, has = pcall(function()
        for _, cp in utf8.codes(s) do if cp >= 0x3040 and cp <= 0x9FFF then return true end end
      end)
      if ok and has then issues[#issues + 1] = "japanese" end
    end
    if #issues > 0 then
      -- only stable positions: sliding notifications start off screen on purpose
      local pkey = scr .. "|" .. s:sub(1, 60)
      local st = seen["pos:" .. pkey]
      if not st or st.x ~= math.floor(x) or st.y ~= math.floor(y) then
        seen["pos:" .. pkey] = { x = math.floor(x), y = math.floor(y), n = 1 }
        return
      end
      st.n = st.n + 1
      if st.n < 4 then return end
      local key = table.concat(issues, ",") .. "|" .. s:sub(1, 40)
      if not seen[key] then
        seen[key] = true
        print(string.format("  [lint] %s %s x=%d y=%d w=%d | %s", scr, table.concat(issues, ","), math.floor(x), math.floor(y),
          math.floor(w), (s:gsub("\n", " / ")):sub(1, 70)))
      end
    end
  end
end
local TEXPATH = { font = "font/main.ntx" }
SNAPSHOT = { pending = nil }

AUDIO = { bgm = 0, se = 0, bgms = {}, ses = {}, missing = {} }
sys = {
  data = DATA,
  tex_load = function(p)
    local f = io.open(map(p), "rb"); if not f then return nil end
    local hdr = f:read(16); f:close()
    local w, h, fmt = string.unpack("<I2I2B", hdr, 5)
    TEXLOADS = (TEXLOADS or 0) + 1
    texid = texid + 1
    TEXBYTES = (TEXBYTES or 0) + w * h * (fmt == 0 and 4 or (fmt == 8 and 1 or 2))
    TEXSIZE[texid] = w * h * (fmt == 0 and 4 or (fmt == 8 and 1 or 2))
    TEXPATH[tostring(texid)] = map(p):sub(#DATA + 1)
    return texid, w, h
  end,
  tex_free = function(id) TEXBYTES = TEXBYTES - (TEXSIZE[id] or 0) end,
  draw = function(id, sx, sy, sw, sh, dx, dy, scx, scy, alpha, tint, blend)
    if REC then REC[#REC + 1] = { "draw", id, sx, sy, sw, sh, dx, dy, scx or 1, scy or scx or 1, alpha or 1, tint or 0xffffffff, blend or 0 } end
  end,
  rect = function(x, y, w, h, c) if REC then REC[#REC + 1] = { "rect", x, y, w, h, c or 0xffffffff } end end,
  scissor = function(x, y, w, h) if REC then REC[#REC + 1] = x and { "clip", x, y, w, h } or { "clip" } end end,
  clear_color = function() end,
  text = function(s, x, y, c, scale, wrap, maxLines)
    local h, w = font_layout(tostring(s), x, y, c or 0xffffffff, scale, wrap, maxLines, REC)
    if LINT then LINT(tostring(s), x, y, w, h, c, wrap, maxLines) end
    return h, w
  end,
  measure = function(s, scale, wrap, maxLines)
    local h, w = font_layout(tostring(s), 0, 0, 0xffffffff, scale, wrap, maxLines, nil)
    return w, h
  end,
  line_height = function() return lh() end,
  -- audio: count what the game plays and flag clips missing from the data folder
  audio_ok = function() return true end,
  bgm_play = function(p)
    local f = io.open(map(p), "rb")
    if not f then AUDIO.missing[p] = true return false end
    f:close(); AUDIO.bgm = AUDIO.bgm + 1; AUDIO.bgms[p:match("[^/]+$")] = true; return true
  end,
  bgm_stop = function() end, bgm_volume = function() end, bgm_pos = function() return 0 end,
  se_load = function(p)
    local f = io.open(map(p), "rb")
    if not f then return nil end
    f:close(); AUDIO.ses[#AUDIO.ses + 1] = p:match("[^/]+$"); return #AUDIO.ses
  end,
  se_free = function() end, se_play = function(id) AUDIO.se = AUDIO.se + 1 end,
  video_open = function() return nil end, video_show = function() end, video_draw = function() end, video_close = function() end,
  read = function(p) local f = io.open(map(p), "rb"); if not f then return nil end local s = f:read("a"); f:close(); return s end,
  write = function(p, d) local f = io.open(map(p), "wb"); if not f then return false end f:write(d); f:close(); return true end,
  exists = function(p)
    if p:find("autoplay.txt", 1, true) then return false end   -- the harness drives its own bot
    local f = io.open(map(p), "rb"); if f then f:close() return true end return false
  end,
  mkdir = function() end,
  remove = function(p) return os.remove(map(p)) end,
  time = function() return now_ms end,
  mem = function() return 30000000, TEXBYTES or 0, collectgarbage("count") * 1024 end,
  keyboard = function() return "hola" end,
  is_new3ds = function() return false end,
}

-- keep the device log (sdmc log.txt, shared with the emulator through the junction) untouched
do
  local open = io.open
  io.open = function(p, m)
    if p == DATA .. "log.txt" then p = PORT .. "/build_data/pc_log.txt" end
    return open(p, m)
  end
end
dofile(PORT .. "/lua/main.lua")
local core = require("runtime.core")
core.debug_cancel = false
core.strict = os.getenv("NGO_STRICT") == "1"
core.fast = os.getenv("NGO_FAST") == "1"
local _LOG = LOG
local echo = { ["[log]"] = true, ["[cancel]"] = true, ["[error]"] = true, TODO = true, missing = true, ["Resources.Load"] = true, achievement = true }
LOG = function(...)
  _LOG(...)
  local first = tostring((...))
  for k in pairs(echo) do if first:find(k, 1, true) then print("  LOG", ...) break end end
end

game.init()
local K = { A = 1, TOUCH = 1 << 20 }
local pending_tap
local function tap(x, y) pending_tap = { x = x, y = y, phase = 0 } end

local frame, lastHist, lastDay, lastPart = 0, 0, -1, -1
local started = false
local function lang() return Settings.CurrentLanguage.Value end

local SNAPDIR = PORT .. "/build_data/snaps/"
os.execute("mkdir \"" .. SNAPDIR:gsub("/", "\\") .. "\" 2>nul")
local snapn, seen_state = 0, {}
local function snap(tag)
  snapn = snapn + 1
  SNAPSHOT.pending = string.format("%s%03d_%s.json", SNAPDIR, snapn, tag)
end
-- one capture the first time each interesting state shows up, plus a periodic one
local function auto_snap()
  if SNAPSHOT.pending then return end
  local function once(key, cond) if cond and not seen_state[key] then seen_state[key] = true; snap(key) return true end end
  if frame == 25 then snap("title") return end
  if not StatusManager.statuses then return end
  local f = WindowManager.focusBottom
  local opts = JineManager._options and JineManager._options.list
  if once("jine_options", opts and opts.n > 0 and f and f.kind == "jine") then return end
  if once("jine", f and f.kind == "jine" and JineManager.history.n > tonumber(os.getenv("NGO_JINE_N") or 6)) then return end
  if once("live", core.views.Live and #core.views.Live.comments > 6) then return end
  if once("live_read", core.views.Live and core.views.Live.isStartRead) then return end
  if once("notif_time", #NotificationManager.items > 0 and NotificationManager.items[#NotificationManager.items].style == "time") then return end
  if once("timepass", WindowManager:isAppOpen("TimePassDialog")) then return end
  if once("neta", WindowManager:isAppOpen("NetaChoose")) then return end
  if once("poketter", f and f.kind == "poketter") then return end
  if once("desktop", not f and StatusManager:GetStatus("DayIndex") >= 2) then return end
  if EventManager.isHorror then
    local d = StatusManager:GetStatus("DayIndex")
    if once("horror_d" .. d .. "_live", core.views.Live and #core.views.Live.comments > 4) then return end
    if once("horror_die", WindowManager:isAppOpen("Die")) then return end
    if once("horror_wrist", WindowManager:isAppOpen("Darkness")) then return end
    if once("horror_kb", WindowManager:isAppOpen("KeijibanMini")) then return end
    local hk = core.ui_state("HakkyoShortCutParent")
    if once("horror_hakkyo", hk.interactable == true) then return end
    if once("horror_poem", Poem.state ~= nil) then return end
    if once("horror_d" .. d, frame % 300 == 0) then return end
  end
  if frame % 6000 == 0 then snap("periodic") end
end

-- UI tour: visit every screen once (day 2 morning) and snapshot it
local TOUR = os.getenv("NGO_TOUR") == "1"
local tour_step, tour_wait = 0, 0
local function tour()
  local B = require("ui.bottom")
  local steps = {
    function() WindowManager:CleanAll(); B.debug_open_menu("internet") return "menu_internet" end,
    function() B.debug_open_menu("ame") return "menu_ame" end,
    function() B.debug_open_menu("okusuri") return "menu_okusuri" end,
    function() B.debug_drug("dypass") return "menu_okusuri_dypass" end,
    function() B.debug_drug(nil); B.debug_open_menu("odekake") return "menu_odekake" end,
    function() B.debug_open_menu("neru") return "menu_neru" end,
    function() B.debug_open_menu(nil); WindowManager:NewWindow_2("NetaChoose") return "neta" end,
    function() WindowManager:CloseApp("NetaChoose"); WindowManager:NewWindow_2("Poketter") return "poketter" end,
    function() WindowManager:CloseApp("Poketter"); WindowManager:NewWindow_2("Jine") return "jine_app" end,
    function() WindowManager:CloseApp("Jine"); B.debug_pause(true) return "pause" end,
    function() B.debug_pause(false); core.views.TimePassDialog:setType("PlayIchatuku", "PlayIchatukuIchatuku"); WindowManager:NewWindow_2("TimePassDialog") return "timepass" end,
    function() WindowManager:CloseApp("TimePassDialog"); WindowManager:NewWindow_2("Internet") return "internet" end,
    function() WindowManager:CloseApp("Internet"); WindowManager:NewWindow_2("Calling") return "calling" end,
    function() WindowManager:CloseApp("Calling"); WindowManager:NewWindow_2("YachinMail") return "mail" end,
    function() WindowManager:CloseApp("YachinMail"); WindowManager:NewWindow_2("Login") return "login" end,
    function() WindowManager:CloseApp("Login"); WindowManager:NewWindow_2("Train") return "train" end,
    function() WindowManager:CloseApp("Train"); WindowManager:NewWindow_2("Hakkyo") return "hakkyo" end,
    function() WindowManager:CloseApp("Hakkyo"); WindowManager:NewWindow_2("Yakujo") return "yakujo" end,
    function() WindowManager:CloseApp("Yakujo"); WindowManager:NewWindow_2("EndingDialog") return "ending_dialog" end,
    function() WindowManager:CloseApp("EndingDialog"); WindowManager:NewWindow_2("TaskManager")
      NotificationManager:add("Jine", "mensaje de prueba de notificación") return "taskmanager_notif" end,
    function() NotificationManager.items = {}; WindowManager:CloseApp("TaskManager"); WindowManager:NewWindow_2("ControlPanel") return "controlpanel" end,
    function() WindowManager:CloseApp("ControlPanel"); ChanceEffectController:OnReach("Chainsaw") return nil end,
    function() return "chance_chainsaw" end,
    function() ChanceEffectController:OnOut(); WindowManager:NewWindow_2("App_Ending_Grand") return nil end,
    function() return "ending_grand" end,
    function() WindowManager:CloseApp("App_Ending_Grand"); WindowManager:NewWindow_2("App_Ending_Netshut") return "ending_netshut" end,
    function() WindowManager:CloseApp("App_Ending_Netshut"); require("ui.bottom").app_module("chipget").cover:getNewChip("Kaidan", 2) return nil end,
    function() return "chipget" end,
    function() require("ui.bottom").app_module("chipget").cover:EndGet()
      for _, a in ipairs({ "Ideon_taiki", "Ideon_2ch", "Ideon_hutaba", "Ideon_nico", "Ideon_news", "Ideon_Insta", "Ideon_wiki" }) do
        WindowManager:NewWindow_2(a)
      end
      return "ideon" end,
    function() WindowManager:CleanAll(); WindowManager:NewWindow_2("Keijiban") return "keijiban" end,
    function() WindowManager:CloseApp("Keijiban"); WindowManager:NewWindow_2("EgosaResult") return nil end,
    function() return "egosa" end,
    function() WindowManager:CleanAll(); WindowManager:NewWindow_2("Dinder") return "dinder" end,
    function() WindowManager:CleanAll(); WindowManager:NewWindow_2("Bank") return nil end,
    function() return "bank" end,
    function() WindowManager:CleanAll(); WindowManager:NewWindow_2("AsobuLust") return "asobulust" end,
    function() WindowManager:CleanAll(); spawn(function() Poem:StartPoem("Internet es un pozo sin fondo.\n\nY aun así es lo único que tengo.", true) end) return nil end,
    function() return "poem" end,
    function() Poem.state = nil; EventManager.nowEnding = "Ending_Meta"
      for _, n in ipairs({ "castwindow", "jimaku", "Button1" }) do core.ui_find(n):SetActive(true) end
      local tmp = core.ui_find("jimakuText"):GetComponent("TMP_Text"); tmp:DOText("...pero ¿quién está mirando?", 1)
      core.ui_find("Button1"):GetComponent("TMP_Text").text = "Soy yo"
      return nil end,
    function() return "meta" end,
    function() for _, n in ipairs({ "castwindow", "jimaku", "Button1" }) do core.ui_find(n):SetActive(false) end
      EventManager.nowEnding = "Ending_Needy"; require("ui.bottom").app_module("endingblue").show() return nil end,
    function() return "endingblue" end,
    function() require("ui.bottom").app_module("endingblue").hide(); EventManager.nowEnding = "Ending_None"
      WindowManager:CleanAll(); WindowManager:NewWindow_2("Darkness") return nil end,
    function() return "wristcut" end,
    function() WindowManager:CleanAll(); game.quit = true return nil end,
  }
  if SNAPSHOT.pending then return end
  tour_wait = tour_wait - 1
  if tour_wait > 0 then return end
  tour_step = tour_step + 1
  local fn = steps[tour_step]
  if not fn then game.quit = true return end
  local tag = fn()
  tour_wait = 40
  if tag then
    -- snapshot a few frames later, once the screen settled
    local due = frame + 20
    TOUR_SNAP = { at = due, tag = tag }
  end
end

-- NGO_BOOST=1: push followers past each story milestone so later days and endings get tested
local BOOST = os.getenv("NGO_BOOST") == "1"
local boosted = {}
local function boost()
  if not (BOOST and StatusManager.statuses) then return end
  local day = StatusManager:GetStatus("DayIndex")
  local goals = { [9] = 15000, [13] = 120000, [16] = 260000, [21] = 300000, [26] = 1100000 }
  local g = goals[day]
  if g and not boosted[day] and StatusManager:GetStatus("Follower") < g then
    boosted[day] = true
    StatusManager:UpdateStatusToNumber("Follower", g)
    print("  >> BOOST followers", g)
  end
end
local EVAL = os.getenv("NGO_EVAL")
local injected = false
local hold_until = 0
local ev = {}
local function bot()
  if EVAL and started and StatusManager.statuses and frame > 200 then
    local fn, err = load(EVAL)
    print("EVAL =>", fn and select(2, pcall(fn)) or err)
    game.quit = true
    return
  end
  -- NGO_INJECT: Lua run once (frame 600) without stopping the game, to jump into a story branch
  local INJ = os.getenv("NGO_INJECT")
  -- NGO_EVENT=<class>: fire that one event on an idle day 2 (the bot keeps answering its JINE,
  -- dialogs and notifications but starts nothing of its own) and report whether it finishes
  local EVT = os.getenv("NGO_EVENT")
  if EVT and EVT ~= "" and (not INJ or INJ == "") then
    INJ = 'rawset(_G, "BOT_HOLD", 1e9); EventManager:AddEvent_2("' .. EVT .. '"); return "' .. EVT .. '"'
  end
  if EVT and EVT ~= "" and injected then
    ev.t0 = ev.t0 or frame
    local busy = EventManager.isEventing or EventManager.eventQueue.Count > 0 or StatusManager.Moved.Value
    if busy then ev.seen, ev.idle = true, 0 else ev.idle = (ev.idle or 0) + 1 end
    if ev.seen and ev.idle > 300 then
      print("EVENT_DONE", EVT, frame - ev.t0) game.quit = true return
    elseif not ev.seen and frame - ev.t0 > 600 then
      print("EVENT_NOSTART", EVT) game.quit = true return
    elseif frame - ev.t0 > 60000 then
      print("EVENT_HANG", EVT, tostring(EventManager.nowEvent or EventManager.executingEvent)) game.quit = true return
    end
  end
  if INJ and INJ ~= "" and started and not injected and frame >= 600 and StatusManager.statuses
     and StatusManager:GetStatus("DayIndex") >= 2 and not EventManager.isEventing and not StatusManager.Moved.Value
     and EventManager.eventQueue.Count == 0 and #NotificationManager.items == 0 and frame % 60 == 30 then
    injected = true
    local fn, err = load(INJ)
    print("  >> INJECT", fn and select(2, pcall(fn)) or err)
    -- the injected code may ask the bot to stay idle for a while (BOT_HOLD frames)
    local hold = rawget(_G, "BOT_HOLD")
    if hold then hold_until = frame + hold end
  end
  if TOUR and started and StatusManager.statuses and StatusManager:GetStatus("DayIndex") >= 2 then return end
  if not started then
    if frame == 30 then
      if os.getenv("NGO_SEED") then math.randomseed(tonumber(os.getenv("NGO_SEED"))) end
      require("ui.main").start_game({ lang = os.getenv("NGO_LANG") or "es", slot = 1, saveFile = os.getenv("NGO_CONT") })
      started = true
      if os.getenv("NGO_DEBUGSC") == "1" then
        local f0 = EventManager.SetShortcutState
        EventManager.SetShortcutState = function(self, on, ...)
          local tb = debug.traceback("", 2):gsub("%s+", " ")
          print("  [sc]", on, "day", StatusManager:GetStatus("DayIndex"), "part", StatusManager:GetStatus("DayPart"), tb:sub(1, 300))
          return f0(self, on, ...)
        end
        local q = PoketterManager._tweetQueue
        local enq = q.Enqueue or q.Add
        local key = q.Enqueue and "Enqueue" or "Add"
        q[key] = function(self, ...)
          print("  [sc] tweet queued; action", tostring(EventManager.executingAction), "day", StatusManager:GetStatus("DayIndex"),
                (debug.traceback("", 2):gsub("%s+", " "):sub(1, 260)))
          return enq(self, ...)
        end
        local f1 = NotificationManager.AddDayPassingNotifier
        NotificationManager.AddDayPassingNotifier = function(self, ...) print("  [sc] AddDayPassingNotifier") return f1(self, ...) end
        local f2 = StatusManager.timePassingToNextMorning
        StatusManager.timePassingToNextMorning = function(self, ...)
          local r = f2(self, ...)
          print("  [sc] nextMorning done: events", EventManager.eventQueue.Count, "tweets", PoketterManager._tweetQueue.Count,
                "eventing", EventManager.isEventing, "token1", tostring(rawget(self, "token1")))
          return r
        end
      end
      if os.getenv("NGO_DEBUGEV") == "1" then
        local q1 = EventManager.AddEventQueue_1
        EventManager.AddEventQueue_1 = function(self, T)
          print("  [ev] queue", T, (debug.traceback("", 2):gsub("%s+", " "):sub(1, 400)))
          return q1(self, T)
        end
      end
    end
    return
  end
  if frame % 20 ~= 0 then return end
  -- JINE options: choose the first one
  local opts = JineManager._options and JineManager._options.list
  if opts and opts.n > 0 then
    local opt = opts.items[1]
    spawn(function() JineManager:AddJineHistory_1(opt) end)
    JineManager:EndOption()
    return
  end
  if JineManager.waitStatus and JineManager.waitStatus.Value == "FreeForm" then JineManager:EndMessage("hola") return end
  -- dialogs
  for _, w in EACH(WindowManager.windows) do
    if w.app == "TimePassDialog" then
      WindowManager:Close(w)
      local p = core.views.TimePassDialog.pending
      print("  >> CONFIRM time pass", p.a)
      spawn(function() EventManager:ExecuteActionConfirmed(p.ac, p.a) end)
      return
    end
    if w.app == "EndingDialog" then print("== ENDING DIALOG:", EventManager.nowEnding); game.quit = true return end
  end
  -- the blue ending screen (EventManager.CallEnding)
  if require("ui.bottom").app_module("endingblue").active() then
    print("== ENDING DIALOG:", EventManager.nowEnding, "(blue screen)")
    game.quit = true
    return
  end
  -- Ending_Meta: answer with the first button shown
  local mc = require("ui.bottom").app_module("metacover")
  if mc.active() and frame % 120 == 0 then
    for _, n in ipairs({ "Button1", "Button2" }) do
      local o = core.ui_objects[n]
      if o and rawget(o, "_active") == true then
        print("  >> META", n)
        core.fire_pointer(o:GetComponent("Button"), "down")
        return
      end
    end
  end
  -- JINE free text (Event_Fetish, Event_Haikuwoyome...): type an answer with the keyboard
  if JineManager.waitStatus and JineManager.waitStatus.Value == "FreeForm" and frame % 60 == 0 then
    print("  >> FREEFORM")
    JineManager:EndMessage("hola")
    return
  end
  -- the new-idea cover (ChipGet_Show): press OK
  local chipget = require("ui.bottom").app_module("chipget")
  if chipget.active() and frame % 60 == 0 then print("  >> CHIP OK"); chipget.cover:EndGet() return end
  -- head-pat minigame
  local nade = require("ui.bottom").app_module("nade")
  if nade.active() then
    nade.amehead.NadeCount.Value = nade.amehead.NadeCount.Value + 1
    print("  >> PAT")
    return
  end
  -- stream: pick superchats / delete bad comments
  local live = core.views.Live
  if live then
    for _, cm in ipairs(live.comments) do if not cm.done and (cm.pickable or cm.p.isBadComment) then live:tapComment(cm) return end end
  end
  -- notifications (time passing etc.)
  local items = NotificationManager.items
  if #items > 0 and frame % 60 == 0 then
    local n = items[#items]
    print(string.format("  [notif %s] %s", n.app, n.text))
    NotificationManager:click(n)
    return
  end
  -- intro: log into the stream account when the shortcut appears
  local login = core.ui_state("LoginShortCut")
  if login.interactable == true and not WindowManager:isAppOpen("Login") and not EventManager.isEventing and frame % 120 == 0 then
    print("  >> LOGIN")
    EventManager:AddEvent_1("Scenario_loop1_day0_night_AfterLogin")
    login.interactable = false
    return
  end
  -- Ending_Happy's Uratter window: open the secret account, then send the follow request
  local ura = WindowManager:find("Uratter")
  if ura and frame % 120 == 0 then
    print("  >> URAURA")
    require("ui.apps.uraura").bot_step(ura)
  end
  -- Ending_Sucide: the liveend icon starts the last stream
  local le = core.ui_objects.liveend
  if le and rawget(le, "_active") == true and not StatusManager.Moved.Value and frame % 120 == 0 then
    print("  >> LIVEEND")
    rawset(le, "_active", false)
    WindowManager:NewWindow_2("Broadcast")
    return
  end
  -- Ending_Ideon: start the last stream from the waiting room
  if WindowManager:find("Ideon_taiki") and not StatusManager.Moved.Value and not EventManager.isEventing and frame % 240 == 0 then
    print("  >> IDEON START")
    EventManager:AddEvent_1("HaishinStart_Ideon")
    return
  end
  -- Ending_Lust / Ending_Needy: the special Play window
  for app, ev in pairs({ AsobuLust = "Action_Inran", AsobuNeedy = "Action_Needy" }) do
    if WindowManager:find(app) and not EventManager.isEventing and not StatusManager.Moved.Value and frame % 240 == 0 then
      print("  >> SPECIAL", app)
      EventManager:AddEvent_1(ev)
      return
    end
  end
  -- the GoOut window (Ame asks to go out): pick a destination the menu offers
  local go = WindowManager:find("GoOut")
  if go and not StatusManager.Moved.Value and frame % 120 == 0 then
    local st = CommandManager.commandStatus and CommandManager.commandStatus.Value
    local opts = {}
    for _, x in ipairs(require("ui.bottom").MENUS.odekake) do
      local s0 = st and st ~= NULL and st:__idx(x)
      if s0 == nil or s0 == "Executable" then opts[#opts + 1] = x end
    end
    if #opts > 0 then
      local a = opts[math.random(#opts)]
      print("  >> GOOUT", a)
      WindowManager:Close(go)
      CommandManager:CommandAction_2(a)
      return
    end
  end
  -- horror day 4: the Hakkyo desktop -> HakkyoDialog -> go on
  local hk = core.ui_state("HakkyoShortCutParent")
  if hk.interactable == true and frame % 120 == 0 then
    local hw = WindowManager:find("Hakkyo")
    if hw then
      print("  >> HAKKYO")
      WindowManager:Close(hw)
      hk.interactable = false
      EventManager:AddEvent_1("Scenario_horror_day4_day_hakkyoed")
    else
      WindowManager:NewWindow_2("Hakkyo")
    end
    return
  end
  -- horror day 3: the Dielog
  local dw = WindowManager:find("Die")
  if dw and not EventManager.isEventing and frame % 240 == 0 then
    print("  >> DIELOG")
    WindowManager:Close(dw)
    EventManager:AddEvent_1("Scenario_horror_day3_day_AfterSine")
    return
  end
  -- the Darkness window (stress event): press its only command
  if WindowManager:find("Darkness") and not StatusManager.Moved.Value and frame % 120 == 0 then
    print("  >> ACTION", "Darkness")
    CommandManager:CommandAction_2("Darkness")
    return
  end
  if frame < hold_until then return end
  -- idle: act (the first night belongs to the tutorial: log in and stream)
  if StatusManager:GetStatus("DayIndex") < 2 then return end
  if StatusManager.Moved.Value or not TaskbarManager.interactive or core.ui_state("ShortCutParent").interactable == false then return end
  if frame % 120 ~= 0 then return end
  local part = StatusManager:GetStatus("DayPart")
  if not WindowManager:isAppOpen("NetaChoose") and part < 2 and math.random() < 0.6 then
    local owned = {}
    for _, a in ipairs({ "Zatudan", "Gamejikkyou", "Otakutalk", "Imbouron", "Kaidan", "ASMR", "Hnahaisin", "Kaisetu", "Taiken", "Yamihaishin", "PR", "Angel" }) do
      local lv = NetaManager:GetAlphaChipLevel(a)
      if lv and lv > 0 then owned[#owned + 1] = { a, lv } end
    end
    if #owned > 0 then
      local pick = owned[math.random(#owned)]
      print("  >> STREAM", pick[1], pick[2]); EventManager:StartHaishin(pick[1], pick[2], "none") return
    end
  end
  local acts = { "PlayIchatuku", "PlayMakeLove", "EntameGame", "InternetYoutube", "InternetPoketter", "InternetPoketterEgosa", "Internet2ch",
                 "InternetDeai", "OdekakeAkihabara", "OdekakeHarajuku", "OdekakeShibuya", "OdekakeNakano", "OkusuriDaypassModerate",
                 "OkusuriPuronModerate", "OkusuriHappa", "OkusuriPsyche", "SleepToTomorrow", "SleepToNight" }
  -- only what the touch UI would offer right now (CommandManager.commandStatus)
  local ok_acts = {}
  local st = CommandManager.commandStatus and CommandManager.commandStatus.Value
  for _, x in ipairs(acts) do
    local s0 = st and st ~= NULL and st:__idx(x)
    local hidden = (x == "SleepToTwilight" and StatusManager:GetStatus("DayPart") > 0) or (x == "SleepToNight" and StatusManager:GetStatus("DayPart") > 1)
    if (s0 == nil or s0 == "Executable") and not hidden and NgoEx.CmdFromType(CommandManager:ChooseCommand_2(x)) then ok_acts[#ok_acts + 1] = x end
  end
  if #ok_acts == 0 then return end
  local a = ok_acts[math.random(#ok_acts)]
  print("  >> ACTION", a)
  CommandManager:CommandAction_2(a)
end

local ok, err = xpcall(function()
  while frame < MAX_FRAMES and not game.quit do
    frame = frame + 1
    now_ms = now_ms + 16
    local down, held, up, tx, ty = 0, 0, 0, 0, 0
    if pending_tap then
      tx, ty = pending_tap.x, pending_tap.y
      if pending_tap.phase == 0 then down = K.TOUCH; held = K.TOUCH; pending_tap.phase = 1
      else up = K.TOUCH; pending_tap = nil end
    end
    bot()
    if started and frame % 5000 == 0 and StatusManager.statuses then
      local wins = {}
      for _, w in EACH(WindowManager.windows) do wins[#wins + 1] = w.app end
      print(string.format("  [diag f%d] eventing=%s moved=%s taskbar=%s shortcuts=%s queue=%d notifs=%d jine=%s wins=%s tasks=%d",
        frame, tostring(EventManager.isEventing), tostring(StatusManager.Moved.Value), tostring(TaskbarManager.interactive),
        tostring(core.ui_state("ShortCutParent").interactable), EventManager.eventQueue.Count, #NotificationManager.items,
        tostring(JineManager.waitStatus.Value), table.concat(wins, ","), #core.sched.tasks))
      print("  [diag] nowEnding", tostring(EventManager.nowEnding))
      if EventManager.nowEnding ~= "Ending_None" then
        local function act(n) local o = core.ui_objects[n]; return o and tostring(rawget(o, "_active")) or "-" end
        print("  [diag] ending", EventManager.nowEnding, "castwindow", act("castwindow"), "jimaku", act("jimaku"),
              "Button1", act("Button1"), "meta", act("meta"), "liveend", act("liveend"))
      end
      if os.getenv("NGO_DEBUGSC") == "1" then
        local t1, t2 = rawget(StatusManager, "token1"), rawget(StatusManager, "token2")
        print("  [sc] tweets", PoketterManager._tweetQueue.Count, "shooting", tostring(PoketterManager.isShootRunning.Value), "view", tostring(core.views.PoketterView2D), "lastAct", tostring(EventManager.executingAction), "t1", t1 and tostring(t1.p and t1.p.dead or t1.fn), "t2", t2 and tostring(t2.p and t2.p.dead or t2.fn))
      end
    end
    local c0 = os.clock()
    game.update(1 / 60, down, held, up, tx, ty)
    local c1 = os.clock()
    boost()
    if TOUR and started and StatusManager.statuses and StatusManager:GetStatus("DayIndex") >= 2 then
      tour()
      if TOUR_SNAP and frame >= TOUR_SNAP.at then snap("tour_" .. TOUR_SNAP.tag); TOUR_SNAP = nil end
    elseif started or frame == 25 then auto_snap() end
    local snap = SNAPSHOT.pending
    if snap then REC = {} end
    game.draw(0)
    local topCmds = REC
    if snap then REC = {} end
    game.draw(1)
    if snap then
      local f = io.open(snap, "w")
      local function jstr(v)
        return '"' .. v:gsub('[%c"\\]', function(ch) return string.format("\\u%04x", ch:byte()) end) .. '"'
      end
      local function enc(v)
        if type(v) == "string" then return jstr(v) end
        if math.type(v) == "float" then return string.format("%.3f", v) end
        return tostring(v)
      end
      local function list(cmds)
        local out = {}
        for _, c in ipairs(cmds or {}) do
          local parts = {}
          for i, v in ipairs(c) do parts[i] = enc(v) end
          out[#out + 1] = "[" .. table.concat(parts, ",") .. "]"
        end
        return "[" .. table.concat(out, ",") .. "]"
      end
      local tex = {}
      for k, v in pairs(TEXPATH) do tex[#tex + 1] = jstr(k) .. ":" .. jstr(v) end
      f:write("{\"textures\":{", table.concat(tex, ","), "},\"top\":", list(topCmds), ",\"bottom\":", list(REC), "}")
      f:close()
      print("  [snap]", snap)
      REC, SNAPSHOT.pending = nil, nil
    end
    local c2 = os.clock()
    PERF = rawget(_G, "PERF") or { u = 0, d = 0, n = 0 }; rawset(_G, "PERF", PERF)
    PERF.u, PERF.d, PERF.n = PERF.u + (c1 - c0), PERF.d + (c2 - c1), PERF.n + 1
    if frame % 5000 == 0 then
      print(string.format("  [perf] update %.2f ms  draw %.2f ms  pollers %d  tasks %d  luaKB %.0f  texloads %d  texMB %.1f",
        PERF.u / PERF.n * 1000, PERF.d / PERF.n * 1000, #core.pollers, #core.sched.tasks, collectgarbage("count"), TEXLOADS or 0, (TEXBYTES or 0) / 1048576))
      print("  [perf] pages", (require("runtime.gfx").stats()))
      TEXLOADS = 0
      rawset(_G, "PERF", nil)
    end
    if started and StatusManager.statuses then
      local day, part = StatusManager:GetStatus("DayIndex"), StatusManager:GetStatus("DayPart")
      if day ~= lastDay or part ~= lastPart then
        print(string.format("=== Día %d franja %d | seg %d estrés %d afecto %d yami %d", day, part,
          StatusManager:GetStatus("Follower"), StatusManager:GetStatus("Stress"), StatusManager:GetStatus("Love"), StatusManager:GetStatus("Yami")))
        lastDay, lastPart = day, part
        if day > MAX_DAYS then break end
      end
      local hist = JineManager.history
      while hist and lastHist < hist.n do
        lastHist = lastHist + 1
        local d = hist.items[lastHist]
        if d.user ~= "separator" and d.user ~= "timeSeparator" then
          local txt = ""
          pcall(function() txt = NgoEx.GetJineHonbun(JineDataConverter.convertJineDataToDrawable(d), lang()) end)
          print(string.format("  JINE[%s] %s", tostring(d.user), tostring(d.stampType ~= "None" and d.stampType or txt):gsub("\r?\n", " ")))
        end
      end
    end
  end
end, debug.traceback)
if not ok then print("ERROR:", err) end
print("frames:", frame, "events:", EventManager.eventsHistory and EventManager.eventsHistory.Count)
do
  local b = {} for k in pairs(AUDIO.bgms) do b[#b + 1] = k end table.sort(b)
  print("audio: bgm starts " .. AUDIO.bgm .. ", se plays " .. AUDIO.se .. ", se clips " .. #AUDIO.ses .. ", bgm clips: " .. table.concat(b, " "))
  for k in pairs(AUDIO.missing) do print("audio MISSING: " .. k) end
end
