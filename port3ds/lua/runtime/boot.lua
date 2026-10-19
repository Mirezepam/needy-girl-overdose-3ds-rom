-- Brings up the game "scene": every manager singleton (fields -> Awake -> Start, like Unity)
-- plus the scene components whose logic matters (stamp replies, phone looking, ...).
local core = require("runtime.core")
local data = require("runtime.data")

local boot = { running = false }

-- order matters for Awake: listeners must exist before EventManager starts the story
local MANAGERS = {
  "Settings", "AudioManager", "StatusManager", "NetaManager", "JineManager", "PoketterManager",
  "WindowManager", "NotificationManager", "TaskbarManager", "TooltipManager", "CursorManager",
  "PostEffectManager", "CommandManager", "WebCamManager", "EventManager",
}
local SCENE_COMPONENTS = { "EventTekitouhenji", "Event_WebCamSumaho", "DayPassing2D" }

core.components = {}

local function is_singleton(C)
  local c = C
  while c do
    if rawget(c, "__name") == "SingletonMonoBehaviour" then return true end
    c = rawget(c, "super")
  end
  return false
end

local function init_fields(C)
  if rawget(C, "__singleton") then return false end
  rawset(C, "__singleton", true)
  if C.__fields then C.__fields(C) end
  core.bind_scene_refs(C, rawget(C, "__name"))
  return true
end

-- singletons first touched after boot are brought up on demand
core.after_load = function(C)
  if boot.running and type(C) == "table" and is_singleton(C) and not rawget(C, "__singleton") then
    init_fields(C)
    if C.Awake then spawn(C.Awake, C) end
    if C.Start then spawn(C.Start, C) end
  end
end

function boot.start_game(opts)
  data.load(opts.lang or "es")
  local list = {}
  for _, name in ipairs(MANAGERS) do
    local C = core.resolve(name)
    if C ~= NULL then list[#list + 1] = C end
  end
  for _, C in ipairs(list) do init_fields(C) end
  -- singletons loaded meanwhile by field initializers get their fields too
  for _, C in pairs(core.classes) do
    if type(C) == "table" and is_singleton(C) and not rawget(C, "__singleton") and rawget(C, "__name") ~= "SingletonMonoBehaviour" then
      init_fields(C)
      list[#list + 1] = C
    end
  end
  boot.running = true
  -- settings decided on the title screen
  Settings.CurrentLanguage.Value = data.LANG_ENUM[data.lang]
  Settings.saveNumber = opts.slot or 1
  Settings.isBackToLoad = opts.saveFile ~= nil
  Settings.nowSaveFile = opts.saveFile or ""
  if opts.haishinSpeed then Settings.haishinSpeed = opts.haishinSpeed end

  for _, name in ipairs(SCENE_COMPONENTS) do
    local obj = NEW(name)
    if obj ~= NULL then
      core.bind_scene_refs(obj, name)
      core.components[name] = obj
      list[#list + 1] = obj
    end
  end
  for _, C in ipairs(list) do
    if C.Awake then spawn(C.Awake, C) end
  end
  for _, C in ipairs(list) do
    if C.Start then spawn(C.Start, C) end
  end
end

-- latest day saved for a slot, or nil
function boot.latest_save(slot)
  for day = 30, 1, -1 do
    local f = string.format("Data%d_Day%d.es3", slot, day)
    if sys.exists("sdmc:/3ds/needy3ds/save/" .. f) then return f, day end
  end
end

return boot
