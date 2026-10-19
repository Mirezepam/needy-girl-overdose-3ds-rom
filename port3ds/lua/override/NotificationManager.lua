-- NotificationManager: same rules as the original (ported from NotificationManager.cs), shown as
-- tappable cards on the bottom screen plus a toast on the top screen.
local core = require("runtime.core")
local data = require("runtime.data")
local C = class("NotificationManager", "SingletonMonoBehaviour")

local function lang() return Settings.CurrentLanguage.Value end
local function systext(id) return NgoEx.SystemTextFromType(id, lang()) end

function C:__fields()
  self.items = {}
  local mgr = self
  -- the game checks _notiferParent.childCount to know if notifications are pending
  self._notiferParent = setmetatable({}, { __index = function(_, k)
    if k == "childCount" then return #mgr.items end
    if k == "GetChild" then return function(_, i) return mgr.items[i + 1] end end
    return NULL
  end })
  self.NotiferParent = self._notiferParent
end

function C:add(app, text, onClick, style)
  local n = { app = app, text = text or "", onClick = onClick, born = core.now(), style = style }
  self.items[#self.items + 1] = n
  return n
end

function C:remove(n)
  for i, x in ipairs(self.items) do if x == n then table.remove(self.items, i) return end end
end

function C:click(n)
  if not n then return end
  if n.onClick then n.onClick() end
end

function C:Awake()
  local mgr = self
  JineManager.OnChangeHistory:Subscribe(function(ev)
    local d = ev.Value
    local u = d.user
    if u ~= "pi" and u ~= "separator" and u ~= "timeSeparator" and u ~= "eventSeparator" then
      AudioManager:PlaySeByType("SE_jine_recieve")
      local w = WindowManager:find("Jine")
      if not w or w._state == "Minimized" or WindowManager.focusBottom ~= w then
        mgr:addJine(NgoEx.GetJineNotificationText(d, lang()))
      end
    end
  end)
  PoketterManager.OnAddQueue:Where(function() return EventManager.executingAction == "None" end)
    :Where(function() return EventManager.nowEnding ~= "Ending_Yarisute" and EventManager.nowEnding ~= "Ending_Av" end)
    :Where(function() return EventManager.isTestScene or StatusManager:GetStatus("DayIndex") ~= 1 end)
    :Subscribe(function()
      if not WindowManager:isAppOpen("Poketter") or not WindowManager:isAppOpen("Result") then
        local text = STR.Replace(systext("New_Tweet_Button"), "X", TOSTR(PoketterManager._tweetQueue.Count))
        mgr:replacePoketter(text)
        core.wait_ms(1200)
      else
        core.wait_ms(1200)
        core.views.PoketterView2D:shootTweetAll()
      end
    end)
  PoketterManager.OnRemoveQueue:Subscribe(function()
    for _, n in ipairs(mgr.items) do if n.app == "Poketter" then mgr:remove(n) break end end
  end)
end

function C:addJine(text)
  local n
  n = self:add("Jine", text, function()
    self:remove(n)
    WindowManager:NewWindow_2("Jine")
  end)
  -- the original removed the notifier when the app window opened
  WindowManager.onChange:Where(function(w) return w and w.app == "Jine" end):Take(1):Subscribe(function() self:remove(n) end)
end

function C:replacePoketter(text)
  for _, n in ipairs(self.items) do
    if n.app == "Poketter" then n.text = text return end
  end
  local n
  n = self:add("Poketter", text, function()
    WindowManager:NewWindow_2("Poketter")
    core.views.PoketterView2D:shootTweetAll()
  end)
end

local function dest_time(t)
  if t == 1 then return systext("System_GO_Daypart1") end
  if t == 2 then return systext("System_GO_Daypart2") end
  return systext("System_GO_NextDay")
end

function C:AddMaturoNotifier()
  AudioManager:PlaySeByType("SE_piyo")
  local txt = lang() == "JP" and "そして……" or "..."
  local n
  n = self:add("Daypart3", txt, function()
    StatusManager:UpdateStatusToNumber("DayPart", 3)
    self:remove(n)
  end, "time")
end

function C:AddTimePassingNotifier(time)
  time = time or 1
  AudioManager:PlaySeByType("SE_piyo")
  local num = time + StatusManager:GetStatus("DayPart")
  local n
  n = self:add("Daypart" .. math.min(num, 3), dest_time(num), function()
    EventManager:AddEvent_2("TimePassing" .. time)
    self:Clean()
  end, "time")
  EventManager:ClearEventQueue()
end

function C:AddDayPassingNotifier()
  AudioManager:PlaySeByType("SE_piyo")
  self:add("Daypart0", dest_time(3), function()
    EventManager:AddEvent_1("DayPassing")
    self:Clean()
  end, "time")
  EventManager:ClearEventQueue()
end

function C:osimai()
  WindowManager:NewWindow_2("EndingDialog"):Uncloseable()
end

function C:AddUrauraNotifier(nakami)
  local n
  n = self:add("Uratter", nakami, function()
    local w = WindowManager:NewWindow_2("Uratter")
    w:Maximize(); w:Uncloseable()
    AudioManager:StopBgm()
    self:remove(n)
  end)
  AudioManager:PlaySeByType("SE_piyo")
end

function C:ChipNotifier(nakami, chip)
  local n
  n = self:add("NetaChoose", nakami, function()
    NetaManager:ShowingGettingChip(chip.alphaType, chip.level)
    self:remove(n)
  end)
end

function C:Clean() self.items = {} end

return C
