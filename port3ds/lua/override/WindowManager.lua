-- WindowManager for two screens. The original opened draggable windows on a 1080p desktop;
-- here every AppType is routed to the top screen (things to watch), the bottom screen (things
-- to touch) or both, following docs/PANTALLAS.md.
local core = require("runtime.core")
local List = core.List
local Subject = core.Subject

local C = class("WindowManager", "SingletonMonoBehaviour")

-- screen: "top" | "bottom" | "both" | "fx" (full-screen effect) | "none"
-- kind: UI module that renders it (ui/apps/<kind>.lua or ui/top scenes)
local ROUTE = {
  Webcam = { "top", "webcam" }, WebcamMini = { "top", "webcam" },
  Jine = { "bottom", "jine" },
  Poketter = { "bottom", "poketter" }, Result = { "bottom", "poketter" }, EndingPoketter = { "bottom", "poketter" },
  Uratter = { "bottom", "poketter" },
  TaskManager = { "top", "stats" }, TaskManagerforResult = { "top", "stats" }, TaskManagerForDebug = { "none" },
  Broadcast = { "both", "live" }, BroadcastMock = { "both", "live" }, LiveDark = { "both", "live" }, ManualHaishin = { "both", "live" },
  NetaChoose = { "bottom", "neta" },
  GoOut = { "bottom", "odekake" }, Train = { "top", "train" }, Train_twilight = { "top", "train" },
  Train_night = { "top", "train" }, Train_Ginga = { "top", "train" },
  Daypart0 = { "top", "daypart" }, Daypart1 = { "top", "daypart" }, Daypart2 = { "top", "daypart" }, Daypart3 = { "top", "daypart" },
  TimePassDialog = { "bottom", "dialog" }, ShutDownDialog = { "bottom", "dialog" }, RebootDialog = { "bottom", "dialog" },
  LoadDialog = { "bottom", "dialog" }, EndingDialog = { "bottom", "dialog" }, sayonalastDialog = { "bottom", "dialog" },
  Psyche1 = { "top", "video" }, Psyche2 = { "top", "video" }, Psyche3 = { "top", "video" }, Psyche4 = { "top", "video" },
  MediaPlayer = { "top", "video" },
  Event_Diary001 = { "both", "doc" }, Event_Diary002 = { "both", "doc" }, Event_Diary003 = { "both", "doc" }, Event_Diary004 = { "both", "doc" },
  MyDocument = { "bottom", "doc" }, TextEditor = { "bottom", "doc" }, Mail = { "bottom", "doc" }, YachinMail = { "bottom", "doc" },
  CrashMail = { "bottom", "doc" }, CrashNakami = { "fx", "crash" }, Sticky = { "bottom", "doc" }, Calendar = { "bottom", "doc" },
  Calling = { "both", "calling" },
  Hakkyo = { "fx", "hakkyo" }, Medama = { "fx", "medama" }, medamaImage = { "fx", "medama" }, Die = { "fx", "die" },
  LastEnd = { "fx", "die" }, Darkness = { "fx", "darkness" }, BrowserCrasher = { "fx", "crash" },
  Ideon_taiki = { "fx", "ideon" }, Ideon_2ch = { "fx", "ideon" }, Ideon_hutaba = { "fx", "ideon" }, Ideon_nico = { "fx", "ideon" },
  Ideon_news = { "fx", "ideon" }, Ideon_Insta = { "fx", "ideon" }, Ideon_wiki = { "fx", "ideon" }, Ideon_webcam = { "fx", "ideon" },
  Sleep = { "top", "sleep" },
  Internet = { "bottom", "tasks" }, Keijiban = { "bottom", "internet" }, KeijibanMini = { "bottom", "internet" },
  EgosaResult = { "bottom", "internet" }, Entame = { "bottom", "tasks" }, Asobu = { "bottom", "tasks" },
  AsobuNeedy = { "bottom", "tasks" }, AsobuLust = { "bottom", "tasks" }, Pills = { "bottom", "tasks" },
  PillDypass = { "bottom", "tasks" }, PillPuron = { "bottom", "tasks" }, PillHipron = { "bottom", "tasks" },
  PillHappa = { "bottom", "tasks" }, PillPsyche = { "bottom", "tasks" }, PillPuron_Horror = { "bottom", "tasks" },
  Dinder = { "bottom", "internet" }, Bank = { "bottom", "doc" }, Yakujo = { "bottom", "doc" },
  Login = { "bottom", "login" }, LoadData = { "bottom", "login" },
  MyPicture = { "both", "pictures" }, ImageViewer = { "both", "pictures" },
  ControlPanel = { "bottom", "settings" }, PsycheNikki1 = { "bottom", "doc" }, PsycheNikki2 = { "bottom", "doc" },
  PsycheNikki3 = { "bottom", "doc" }, PsycheNikki4 = { "bottom", "doc" }, FirstDiary = { "bottom", "doc" }, HintTextAfterEnding = { "bottom", "doc" },
  App_Ending_Grand = { "both", "ending" }, App_Ending_Netshut = { "both", "ending" },
  Ideon_hutaba_ = { "fx", "ideon" }, Test = { "none" }, None = { "none" },
}

local Window = {}
Window.__index = function(t, k)
  if k == "windowState" then return t._state end
  if k == "nakami" or k == "gameObject" then return t end
  return Window[k] or NULL
end

function Window:GetComponent(name)
  local view = core.views and core.views[name]
  if view then return view end
  return NULL
end
function Window:Uncloseable() self.closeable = false; return self end
function Window:Closeable() self.closeable = true; return self end
function Window:UnMovable() return self end
function Window:Maximize() self.maximized = true; return self end
function Window:Minimize() self._state = "Minimized" end
function Window:Touched() C:Touched(self) end
function Window:SetActive(v) if not v then C:Close(self) end end
Window.transform = NULL

function C:__fields()
  self.windows = List.new()     -- open windows, oldest first
  self.WindowList = self.windows
  self.TaskBarList = List.new()
  self.onChange = Subject.new()
  self.focusBottom = nil
end

function C:Awake() end
function C:Start() end

function C.route(app) return ROUTE[app] or { "bottom", "doc" } end

function C:find(app)
  for _, w in EACH(self.windows) do if w.app == app then return w end end
end

function C:open(app, opts)
  if app == nil or app == NULL then return NULL end
  local r = C.route(app)
  if r[1] == "none" then return setmetatable({ app = app, screen = "none" }, Window) end
  local w = self:find(app)
  if not w then
    w = setmetatable({ app = app, screen = r[1], kind = r[2], closeable = true, _state = "Normal", opened = core.now() }, Window)
    self.windows:Add(w)
  end
  w._state = "Normal"
  w.opened = core.now()
  if (w.screen == "bottom" or w.screen == "both") and w.kind ~= "dialog" then self.focusBottom = w end
  if opts and opts.playSe ~= false and AudioManager.PlaySeByType then AudioManager:PlaySeByType("SE_window_open") end
  self.onChange:OnNext(w)
  -- PoketterView.Awake: an opened Poketter / Result window shoots the queued tweets
  if w.kind == "poketter" and PoketterManager._tweetQueue and PoketterManager._tweetQueue.Count > 0 then
    local view = core.views.PoketterView2D
    if view then spawn(function() view:shootTweetAll() end) end
  end
  return w
end

-- overloads (see original signatures): NewWindow(app, parent) / NewWindow(app, playSe) / NewWindow(name)
function C:NewWindow_1(app) return self:open(app) end
function C:NewWindow_2(app, playSe) return self:open(app, { playSe = playSe }) end
function C:NewWindow_3(name) return self:open(name) end
function C:NewWindow_Compact(app, playSe) return self:open(app, { playSe = playSe }) end
function C:NewWindow_NoInteractive(app) return self:open(app) end

function C:GetWindowFromApp(app) return self:find(app) or NULL end
function C:GetNakamiFromApp(app) return self:find(app) or self:open(app) end
function C:isAppOpen(app) return self:find(app) ~= nil end
function C:isAppActive(app) local w = self:find(app); return w ~= nil and w._state ~= "Minimized" end
function C:Count() return self.windows.n end

function C:Close(w)
  if not w or w == NULL then return end
  self.windows:Remove(w)
  if self.focusBottom == w then
    self.focusBottom = nil
    for i = self.windows.n, 1, -1 do
      local o = self.windows.items[i]
      if (o.screen == "bottom" or o.screen == "both") and o._state ~= "Minimized" and o.kind ~= "dialog" then self.focusBottom = o; break end
    end
  end
  self.onChange:OnNext(nil)
end

function C:CloseApp(app) self:Close(self:find(app)) end
function C:MinifyApp(app) local w = self:find(app); if w then w._state = "Minimized"; if self.focusBottom == w then self.focusBottom = nil end end end
function C:Minimize(w) if w and w ~= NULL then self:MinifyApp(w.app) end end
function C:Pop(w) if w and w ~= NULL then w._state = "Normal"; self:Touched(w) end end
function C:Touched(w)
  if not w or w == NULL then return end
  w._state = "Normal"
  if (w.screen == "bottom" or w.screen == "both") and w.kind ~= "dialog" then self.focusBottom = w end
end
C.SetForeground = C.Touched
function C:ActivateFirst() end
function C:Uncloseable_1(w) if w and w ~= NULL then w.closeable = false end end
function C:Uncloseable_2(app) local w = self:find(app); if w then w.closeable = false end end
function C:Closeable(app) local w = self:find(app); if w then w.closeable = true end end
function C:UnMovable_1() end
function C:UnMovable_2() end
function C:MakeTaskButton() end
function C:RegistPresetWindow() end
function C:getTaskbarByWindow() return NULL end

local keep = { Webcam = true, WebcamMini = true }
function C:CleanAll()
  for i = self.windows.n, 1, -1 do
    local w = self.windows.items[i]
    if not keep[w.app] then self.windows:RemoveAt(i - 1) end
  end
  self.focusBottom = nil
  self.onChange:OnNext(nil)
end
function C:Clean() self:CleanAll() end
function C:CleanOnLoad() self:CleanAll() end
function C:CleanOnCommand(is2ch, isDeai)
  -- the original closed everything except the webcam (and the board / dating app when relevant)
  for i = self.windows.n, 1, -1 do
    local w = self.windows.items[i]
    if not keep[w.app] and not (is2ch and w.app == "Keijiban") and not (isDeai and w.app == "Dinder") then
      self.windows:RemoveAt(i - 1)
    end
  end
  self.focusBottom = nil
end
function C:CleanWindowCalmly() self:CleanAll() end
function C:DieOut() self:CleanAll() end
function C:LoveOut() self:CleanAll() end

-- window shown on the top screen right now (highest priority)
local TOP_PRIORITY = { video = 9, ideon = 8, train = 7, daypart = 6, sleep = 6, live = 5, calling = 4, doc = 3, pictures = 3, ending = 3, stats = 1, webcam = 0 }
function C:topWindow()
  local best, bp
  for _, w in EACH(self.windows) do
    if (w.screen == "top" or w.screen == "both") and w._state ~= "Minimized" then
      local p = TOP_PRIORITY[w.kind] or 2
      if not bp or p >= bp then best, bp = w, p end
    end
  end
  return best
end

function C:fxWindows()
  local r = {}
  for _, w in EACH(self.windows) do if w.screen == "fx" then r[#r + 1] = w end end
  return r
end

return C
