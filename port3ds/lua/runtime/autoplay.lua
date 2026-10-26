-- Development autoplay: plays the game by itself (JINE options, notifications, streams, actions)
-- so builds can be tested on an emulator without input. Enabled only when
-- sdmc:/3ds/needy3ds/autoplay.txt exists; the PC harness uses the same logic.
local core = require("runtime.core")

local A = { enabled = false, frame = 0, log = function() end }

local ACTS = { "PlayIchatuku", "PlayMakeLove", "EntameGame", "InternetYoutube", "InternetPoketter", "InternetPoketterEgosa",
               "Internet2ch", "InternetDeai", "OdekakeAkihabara", "OdekakeHarajuku", "OdekakeShibuya", "OdekakeNakano",
               "OkusuriDaypassModerate", "OkusuriPuronModerate", "OkusuriHappa", "OkusuriPsyche",
               "SleepToTomorrow", "SleepToNight" }
local ALPHAS = { "Zatudan", "Gamejikkyou", "Otakutalk", "Imbouron", "Kaidan", "ASMR", "Hnahaisin", "Kaisetu", "Taiken",
                 "Yamihaishin", "PR", "Angel" }

function A.step()
  A.frame = A.frame + 1
  local frame = A.frame
  if not StatusManager.statuses or frame % 20 ~= 0 then return end
  local opts = JineManager._options and JineManager._options.list
  if opts and opts.n > 0 then
    local opt = opts.items[math.random(opts.n)]
    spawn(function() JineManager:AddJineHistory_1(opt) end)
    JineManager:EndOption()
    return
  end
  if JineManager.waitStatus and JineManager.waitStatus.Value == "FreeForm" then JineManager:EndMessage("hola") return end
  for _, w in EACH(WindowManager.windows) do
    if w.app == "TimePassDialog" then
      WindowManager:Close(w)
      local p = core.views.TimePassDialog.pending
      A.log("confirm time pass", p.a)
      spawn(function() EventManager:ExecuteActionConfirmed(p.ac, p.a) end)
      return
    end
    if w.app == "EndingDialog" then A.ending = EventManager.nowEnding; return end
  end
  if require("ui.bottom").app_module("endingblue").active() then A.ending = EventManager.nowEnding; return end
  -- Ending_Meta: answer with the first button shown
  local mc = require("ui.bottom").app_module("metacover")
  if mc.active() and frame % 120 == 0 then
    for _, n in ipairs({ "Button1", "Button2" }) do
      local o = core.ui_objects[n]
      if o and rawget(o, "_active") == true then
        core.fire_pointer(o:GetComponent("Button"), "down")
        return
      end
    end
  end
  local chipget = require("ui.bottom").app_module("chipget")
  if chipget.active() and frame % 60 == 0 then A.log("chip ok"); chipget.cover:EndGet() return end
  local nade = require("ui.bottom").app_module("nade")
  if nade.active() then nade.amehead.NadeCount.Value = nade.amehead.NadeCount.Value + 1 return end
  local live = core.views.Live
  if live then
    for _, cm in ipairs(live.comments) do
      if not cm.done and (cm.pickable or cm.p.isBadComment) then live:tapComment(cm) return end
    end
  end
  -- Ending_Happy's Uratter window: open the secret account, then send the follow request
  local ura = WindowManager:find("Uratter")
  if ura and frame % 120 == 0 then
    A.log("uraura")
    require("ui.apps.uraura").bot_step(ura)
    return
  end
  -- Ending_Sucide: the liveend icon starts the last stream
  local le = core.ui_objects.liveend
  if le and rawget(le, "_active") == true and not StatusManager.Moved.Value and frame % 120 == 0 then
    A.log("liveend")
    rawset(le, "_active", false)
    WindowManager:NewWindow_2("Broadcast")
    return
  end
  -- Ending_Ideon: start the last stream from the waiting room
  if WindowManager:find("Ideon_taiki") and not StatusManager.Moved.Value and not EventManager.isEventing and frame % 240 == 0 then
    A.log("ideon start")
    EventManager:AddEvent_1("HaishinStart_Ideon")
    return
  end
  -- Ending_Lust / Ending_Needy: the special Play window
  for app, ev in pairs({ AsobuLust = "Action_Inran", AsobuNeedy = "Action_Needy" }) do
    if WindowManager:find(app) and not EventManager.isEventing and not StatusManager.Moved.Value and frame % 240 == 0 then
      A.log("special", app)
      EventManager:AddEvent_1(ev)
      return
    end
  end
  -- GoOut window (Ame asks to go out): pick a destination the menu offers
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
      A.log("goout", a)
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
      A.log("hakkyo")
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
    A.log("dielog")
    WindowManager:Close(dw)
    EventManager:AddEvent_1("Scenario_horror_day3_day_AfterSine")
    return
  end
  -- Darkness window (stress event): its only command
  if WindowManager:find("Darkness") and not StatusManager.Moved.Value and frame % 120 == 0 then
    A.log("darkness")
    CommandManager:CommandAction_2("Darkness")
    return
  end
  local login = core.ui_state("LoginShortCut")
  if login.interactable == true and frame % 120 == 0 then
    A.log("login")
    EventManager:AddEvent_1("Scenario_loop1_day0_night_AfterLogin")
    login.interactable = false
    return
  end
  local items = NotificationManager.items
  if #items > 0 and frame % 60 == 0 then
    local n = items[#items]
    A.log("notif", n.app, n.text)
    NotificationManager:click(n)
    return
  end
  if StatusManager:GetStatus("DayIndex") < 2 then return end
  if StatusManager.Moved.Value or not TaskbarManager.interactive or core.ui_state("ShortCutParent").interactable == false then return end
  if frame % 120 ~= 0 then return end
  if not WindowManager:isAppOpen("NetaChoose") and StatusManager:GetStatus("DayPart") < 2 and math.random() < 0.6 then
    local owned = {}
    for _, a in ipairs(ALPHAS) do
      local lv = NetaManager:GetAlphaChipLevel(a)
      if lv and lv > 0 then owned[#owned + 1] = { a, lv } end
    end
    if #owned > 0 then
      local pick = owned[math.random(#owned)]
      A.log("stream", pick[1], pick[2])
      EventManager:StartHaishin(pick[1], pick[2], "none")
      return
    end
  end
  -- prefer actions that hint a new stream topic (that is how chips are found)
  local hinted, ok_acts = {}, {}
  local st = CommandManager.commandStatus and CommandManager.commandStatus.Value
  for _, x in ipairs(ACTS) do
    local s0 = st and st ~= NULL and st:__idx(x)
    local hidden = (x == "SleepToTwilight" and StatusManager:GetStatus("DayPart") > 0) or (x == "SleepToNight" and StatusManager:GetStatus("DayPart") > 1)
    local ok, cmd = pcall(function() return NgoEx.CmdFromType(CommandManager:ChooseCommand_2(x)) end)
    if (s0 == nil or s0 == "Executable") and not hidden and ok and cmd then
      ok_acts[#ok_acts + 1] = x
      if CommandManager:isHinted(x) then hinted[#hinted + 1] = x end
    end
  end
  local pool = (#hinted > 0 and math.random() < 0.7) and hinted or ok_acts
  if #pool == 0 then return end
  local a = pool[math.random(#pool)]
  A.log("action", a)
  CommandManager:CommandAction_2(a)
end

return A
