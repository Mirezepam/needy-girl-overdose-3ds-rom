-- Live (stream) controller: the transpiled game logic (scenario choice, mob comments, speed,
-- reading picked comments) with its Unity UI calls replaced by state the 3DS view draws.
local core = require("runtime.core")
local G = require("runtime.gfx")
local List = core.List
local C = require("gen.Live")

local SC_COLORS = { Blue = 0xa1b7f0ff, Cyan = 0x8bd5ffff, LightGreen = 0x8dffc6ff, Yellow = 0xfaff8dff,
                    Orange = 0xffca10ff, Magenta = 0xeaa0e8ff, Red = 0xe75252ff }
local SC_ORDER = { "Red", "Blue", "Cyan", "LightGreen", "Yellow", "Orange", "Magenta", "Red" }
C.SC_COLORS = SC_COLORS

local fields = C.__fields
function C:__fields()
  fields(self)
  self.comments = {}         -- {p, text, color, pickable, picked, deleted, born}
  self.tray = {}             -- picked comments waiting to be read (max 2)
  self.jimaku = nil          -- {text, t0, dur}
  self.anim = { name = "stream_cho_akaruku", t0 = core.now(), loop = true }
  self.anti = nil
  self.watcher = 0
  self.bg = "bg_stream"
end

local function choose_bg(self)
  local f = StatusManager:GetStatus("Follower")
  local day = StatusManager:GetStatus("DayIndex")
  local bg = "bg_stream"
  if f > 100000 and day > 14 then bg = "bg_stream_shield_silver" end
  if f > 1000000 and day > 27 then bg = "bg_stream_shield_gold" end
  if EventManager.alpha == "Angel" then bg = "bg_stream_angel_lv" .. math.min(5, math.max(1, EventManager.alphaLevel)) end
  if EventManager.nowEnding == "Ending_Kyouso" then bg = "bg_stream_kyouso" end
  if EventManager.isHorror and day >= 28 then bg = "bg_stream_horror" end
  if EventManager.nowEnding == "Ending_Happy" then bg = "bg_stream_gold" end
  if EventManager.nowEnding == "Ending_Sucide" then bg = "bg_stream_sayonara_002" end
  if EventManager.nowEnding == "Ending_Grand" then bg = "bg_stream_grandend" end
  self.bg = bg
end

function C:Awake()
  self._lang = Settings.CurrentLanguage.Value
  self.Speed = Settings.haishinSpeed or 0
  self.statusDiffs = List.new()
  self:chotenView(EventManager.alpha, EventManager.beta)
  choose_bg(self)
  pcall(self.bgView, self)
  self.noChair = StatusManager:GetStatus("DayIndex") < 11 or (EventManager.alpha == "Hnahaisin" and EventManager.alphaLevel == 4)
    or (EventManager.alpha == "ASMR" and EventManager.alphaLevel == 5) or EventManager.alpha == "Angel"
  self.watcher = math.max(math.floor(StatusManager:GetStatus("Follower") / 5), 192)
  if EventManager.nowEnding == "Ending_DarkAngel" then self.watcher = 1000422 end
  if EventManager.nowEnding == "Ending_Ideon" then self.watcher = 100000000 end
  self:SetScenario_1()
  self.haisinTitle = self.NowPlaying and self.NowPlaying.title or ""
  self:setSpeed_2()
end

-- SetScenario(): transpiled decision logic; SetScenario<T>() / SetScenario(string) instantiate here
local function instantiate(self, name)
  LOG("[live] scenario", name, "day", StatusManager:GetStatus("DayIndex"))
  local sc = NEW(name)
  if sc == NULL then sc = NEW("TestScenario") end
  self.NowPlaying = sc
  sc:Awake()
  sc._Live = self
  self.scenarioLength = sc.playing.Count
  self.haisinTitle = sc.title
  spawn(function() sc:StartScenario() end)
  return sc
end
function C:SetScenario_2(name) return instantiate(self, name) end
function C:SetScenario_3(name) return instantiate(self, name) end

function C:ChotenAnimation(name, loop)
  if type(name) ~= "string" or #name <= 1 then return end
  local cur = self.anim
  local clip = G.find_clip(name)
  if cur and cur.name == name and name ~= "stream_cho_akaruku" and clip and clip.loop then return end
  self.anim = { name = name, t0 = core.now(), loop = loop ~= false }
end

function C:NewComment(p)
  local text = p.nakami or ""
  local c = { p = p, text = text, born = core.now() }
  if p.color and p.color ~= "White" then
    c.color = SC_COLORS[p.color]
  elseif (p.henji or "") ~= "" or (self.isOiwai and math.random(0, 2) < 2) then
    c.color = SC_COLORS[SC_ORDER[math.random(1, #SC_ORDER)]]
    c.pickable = true
    AudioManager:PlaySeByType("SE_superchat")
  end
  self.comments[#self.comments + 1] = c
  if #self.comments > 60 then table.remove(self.comments, 1) end
  self.watcher = self.watcher + math.random(-1, 1)
end

-- the stylus is on a comment: pause like the original mouse hover
function C:hover(on)
  if not self.NowPlaying then return end
  if on and self:isActiveReaction() then self.NowPlaying.isGensoku.Value = true
  elseif not on then self.NowPlaying.isGensoku.Value = false end
end

-- tap on a comment: pick a superchat (hirou) or delete a normal one (sakujo)
function C:tapComment(c)
  if c.done or not self:isActiveReaction() then return end
  if EventManager.isHorror and StatusManager:GetStatus("DayIndex") == 29 and not c.pickable then return end
  c.done = true
  self.NowPlaying.isGensoku.Value = false
  if c.pickable then
    self:hirowareta(c.p)
  else
    AudioManager:PlaySeByType("SE_pien")
    c.deleted = true
    local p = c.p
    if p.delta ~= 0 and p.diffStatusType ~= "Tension" then
      spawn(function() StatusManager:UpdateStatus(p.diffStatusType, p.delta) end)
    end
  end
  self:Actioned()
end

function C:hirowareta(p)
  if self.NowPlaying.playing.Count == 0 then return end
  AudioManager:PlaySeByType("SE_kirarin")
  if #self.tray >= 2 then table.remove(self.tray, 1) end
  self.tray[#self.tray + 1] = p
end

-- ReadComment ported from Live.cs, reading from the tray instead of the Unity hierarchy
function C:ReadComment()
  self.isStartRead = true
  self.NowPlaying.isGensoku.Value = false
  if #self.tray == 0 then return end
  local lang = Settings.CurrentLanguage.Value
  local list = List.new()
  local serihu = self.ReadingSerihu
  if self:isYomiReactionExist(EventManager.alpha, EventManager.alphaLevel) then
    local anim = self:getReadAnimationFromHaishin(EventManager.alpha, EventManager.alphaLevel)
    local line = NgoEx.TenTalk_2(IDX(serihu, Random.Range(0, serihu.Count)), lang)
    if anim ~= "" then
      list:Add(NEW("Playing", 1, true, line, "Tension", 1, 0, "", "", anim))
    else
      list:Add(NEW("Playing", 1, true, line))
    end
  end
  local q1, q2 = lang == "EN" and "\"" or "「", lang == "EN" and "\"" or "」"
  for _, p in ipairs(self.tray) do
    list:Add(NEW("Playing", 1, true, q1 .. p.nakami .. q2, "Tension", p.additionalTension))
    if p.henji ~= "" then
      self:SuperChattedChotenAnim()
      local texts = STR.Split(p.henji, "___")
      local anims = STR.Split(p.henjiAnim or "", "___")
      for j = 0, texts.Count - 1 do
        local t = texts:__idx(j)
        if t ~= "" then
          local a = anims:__idx(math.max(0, math.min(j, anims.Count - 1))) or ""
          list:Add(NEW("Playing", 1, true, t, "Tension", 1, 0, "", "", a, p.isLoopAnim))
        end
      end
    end
  end
  self.tray = {}
  self.NowPlaying.playing:InsertRange(1, list)
end

function C:ShowJimaku(p)
  local per = self.isHayakuti and 0.02 or 0.05
  local text = (p.nakami or ""):gsub("<br>", "\n")
  local len = utf8.len(text) or #text
  self.jimaku = { text = text, t0 = core.now(), dur = len * per, len = len }
  self.isSpeaking = true
  local j = self.jimaku
  local I = core.input
  core.wait_until(function() return core.now() - j.t0 >= j.dur or j.skip end)
  j.dur = 0
  core.wait_ms(Constants.FAST / 8)
  self.isSpeaking = false
end

function C:NextSerihu()
  if self.isSpeaking and self.jimaku then self.jimaku.skip = true
  elseif self.NowPlaying then self.NowPlaying:PlayScenarioToNextSerihu() end
end

function C:setAnti(text, on)
  self.anti = on and text or nil
  if on then AudioManager:PlaySeByType("SE_tweet_kusorep") end
end

function C:UpdateDetail() end
function C:RefreshYomuCommentLabel() end
function C:CommentScrollToLatest() end
function C:bgView() choose_bg(self) end

-- Speed: the transpiled setSpeed reads UI labels; keep only its effect
function C:setSpeed_2()
  local sc = self.NowPlaying
  if not sc then return end
  AudioManager:PlaySeByType("SE_piporo")
  local s = self.Speed or 0
  if s == 0 then sc.STARTSPEED = sc.TOGGLEDBASESPEED; self.isHayakuti = false
  elseif s == 1 then sc.STARTSPEED = IDIV(sc.TOGGLEDBASESPEED, 3); self.isHayakuti = true
  else sc.STARTSPEED = IDIV(sc.TOGGLEDBASESPEED, 10); self.isHayakuti = true end
  Settings.haishinSpeed = s
end
function C:setSpeed_1(speed) self.Speed = speed; self:setSpeed_2() end
function C:ToggleSpeed() if not self._lockSpeed then self.Speed = ((self.Speed or 0) + 1) % 3; self:setSpeed_2() end end
function C:DownSpeed() if not self._lockSpeed then self.Speed = ((self.Speed or 0) + 2) % 3; self:setSpeed_2() end end
function C:SetSpeedLock(v) self._lockSpeed = v end
function C:Skip() if self.NowPlaying then self.NowPlaying:SkipScenario() end end

C.__getters.CommentScroll = function() return NULL end
-- TenchanView: the broadcast picture. Background sprite fields hold sprite names; assigning
-- _backGround.sprite changes what ui/live.lua draws. End card = stream_cho_end.
local BG_FIELDS = {
  background_silver_shield = "bg_stream_shield_silver", background_gold_shield = "bg_stream_shield_gold",
  background_kinen1 = "bg_stream_angel_lv1", background_kinen2 = "bg_stream_angel_lv2",
  background_kinen3 = "bg_stream_angel_lv3", background_kinen4 = "bg_stream_angel_lv4",
  background_kinen5 = "bg_stream_angel_lv5", _background_kyouso = "bg_stream_kyouso",
  _background_horror = "bg_stream_horror", _background_happy = "bg_stream_gold",
  _background_ntr = "bg_stream_mansion", _background_sayonara1 = "bg_stream_sayonara_002",
}
local NO_END_CARD = { Ending_Meta = true, Ending_KowaiInternet = true, Ending_Kyouso = true,
                      Ending_Grand = true, Ending_Sucide = true, Ending_Ginga = true }
local function tenchan(live)
  local t = rawget(live, "_tenchan")
  if t then return t end
  local bgobj = setmetatable({}, {
    __index = function(_, k) if k == "sprite" then return live.bg end return NULL end,
    __newindex = function(_, k, v)
      if k == "sprite" and type(v) == "string" then live.bg = v end
      if k == "color" and EventManager.nowEnding == "Ending_Grand" then live.bg = "bg_stream_grandend" end
    end,
  })
  t = setmetatable({ _backGround = bgobj }, { __index = function(_, k)
    if BG_FIELDS[k] then return BG_FIELDS[k] end
    if k == "LiveEnd" then return live.endCard == true end
    if k == "CurrentAnim" then return live.anim and live.anim.name end
    return NULL
  end })
  function t:PlayAnim(name) live:ChotenAnimation(name) end
  function t:PlayAnimOneShot(name) live:ChotenAnimation(name) end
  function t:HideGirl() live.hideGirl = true end
  function t:ShowEndView()
    AudioManager:PlaySeByType("SE_endHaishin")
    live.endCard = true
  end
  function t:ReWindEndView() live.endCard = false end
  function t:OnEndStream()
    local e = EventManager.nowEnding
    if NO_END_CARD[e] or e == "Ending_DarkAngel" then return end
    t:ShowEndView()
  end
  rawset(live, "_tenchan", t)
  return t
end
C.__getters.Tenchan = function(self) return tenchan(self) end
C.__getters._HaisinSpeed = function() return NULL end
C.__getters._HaisinSkip = function() return NULL end

return C
