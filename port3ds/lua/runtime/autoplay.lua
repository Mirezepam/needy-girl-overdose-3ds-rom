-- Development autoplay: plays the game by itself (JINE options, notifications, streams, actions)
-- so builds can be tested on an emulator without input. Enabled only when
-- sdmc:/3ds/needy3ds/autoplay.txt exists; the PC harness uses the same logic.
local core = require("runtime.core")

local A = { enabled = false, frame = 0, log = function() end }

local ACTS = { "PlayIchatuku", "PlayMakeLove", "EntameGame", "InternetYoutube", "InternetPoketter", "InternetPoketterEgosa",
               "Internet2ch", "InternetDeai", "OdekakeAkihabara", "OdekakeHarajuku", "OdekakeShibuya", "OdekakeNakano",
               "OkusuriDaypassModerate", "OkusuriPuronModerate", "OkusuriHipuronModerate", "OkusuriHappa", "OkusuriPsyche",
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
  local nade = require("ui.bottom").app_module("nade")
  if nade.active() then nade.amehead.NadeCount.Value = nade.amehead.NadeCount.Value + 1 return end
  local live = core.views.Live
  if live then
    for _, cm in ipairs(live.comments) do
      if not cm.done and (cm.pickable or cm.p.isBadComment) then live:tapComment(cm) return end
    end
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
