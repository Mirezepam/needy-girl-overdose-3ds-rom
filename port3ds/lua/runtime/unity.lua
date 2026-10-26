-- Unity / .NET shims used by the transpiled game code. Anything purely visual that the 3DS
-- UI replaces resolves to NULL (absorbs calls) instead of being emulated.
local core = require("runtime.core")
local List = core.List
local classes = core.classes

-- ------------------------------------------------------------------ base object behaviour
local ObjectBase = {}
core.ObjectBase = ObjectBase
function ObjectBase:ObserveEveryValueChanged(fn) return core.every_value_changed(self, fn) end
function ObjectBase:ToString() return rawget(getmetatable(self) or {}, "__name") or "Object" end
function ObjectBase:Equals(o) return self == o end
function ObjectBase:GetHashCode() return 0 end
function ObjectBase:GetType() return { Name = (getmetatable(self) or {}).__name } end
core.default_tostring = ObjectBase.ToString

-- GameObject stand-in: real enough for ObserveEveryValueChanged / SetActive / GetComponent
local GameObject = setmetatable({ __name = "GameObject" }, { __index = ObjectBase })
GameObject.__index = function(t, k)
  if k == "transform" then return t._transform end
  if k == "activeSelf" or k == "activeInHierarchy" then return t._active end
  return GameObject[k] or NULL
end
classes.GameObject = GameObject
function GameObject.new(name)
  return setmetatable({ name = name or "GameObject", _active = true, _transform = NULL, _components = {} }, GameObject)
end
function GameObject:SetActive(v) rawset(self, "_active", v) end
-- components of named scene objects are plain state tables the 3DS UI reads (CanvasGroup, ...)
local COMPONENT_DEFAULTS = { CanvasGroup = { alpha = 1, interactable = true, blocksRaycasts = true } }
function GameObject:GetComponent(t)
  local comp = self._components[t]
  if comp then return comp end
  if core.components and core.components[t] then return core.components[t] end
  comp = core.make_component(self, t)
  for k, v in pairs((core.ui_defaults[self.name] or {})[t] or {}) do comp[k] = v end
  self._components[t] = comp
  return comp
end

-- component state table: Unity-like fields default to NULL; pointer/click streams the UI can fire
local Component = {}
local POINTER = { OnPointerDownAsObservable = "down", OnClickAsObservable = "click", OnPointerClickAsObservable = "click",
                  OnPointerEnterAsObservable = "enter", OnPointerExitAsObservable = "exit", OnPointerUpAsObservable = "up" }
function core.make_component(go, t)
  local comp = setmetatable({ __type = t }, { __index = function(c, k)
    if k == "gameObject" then return go end
    if POINTER[k] then
      return function(self)
        -- rawget: __index answers NULL for unknown fields
        local subs = rawget(self, "__subjects")
        if not subs then subs = {}; rawset(self, "__subjects", subs) end
        local s = subs[POINTER[k]]
        if not s then s = core.Subject.new(); subs[POINTER[k]] = s end
        return s
      end
    end
    if k == "GetComponent" or k == "GetComponentInChildren" then return function(_, tt) return go:GetComponent(tt) end end
    -- DOTween text: the text appears at once (the UI types it out from .text)
    if k == "DOText" then return function(self, text) rawset(self, "text", text); rawset(self, "_t0", core.now and core.now() or 0); return NULL end end
    return NULL
  end })
  for k, v in pairs(COMPONENT_DEFAULTS[t] or {}) do comp[k] = v end
  return comp
end
-- the UI calls this when the player taps a scene object (e.g. the full-screen "cover")
function core.fire_pointer(comp, kind)
  local s = comp and rawget(comp, "__subjects") and comp.__subjects[kind or "down"]
  if s then s:OnNext({}) end
  if kind == "down" or kind == nil then
    local c = rawget(comp, "__subjects") and comp.__subjects.click
    if c then c:OnNext({}) end
  end
end
GameObject.OnPointerDownAsObservable = function(self) return self:GetComponent("Image"):OnPointerDownAsObservable() end

-- scene references declared on components: give each one a named UI object (schemas from cs2lua)
local schemas
function core.bind_scene_refs(obj, className)
  schemas = schemas or require("schemas")
  local c = core.classes[className]
  while c do
    local sc = schemas[rawget(c, "__name") or ""]
    if sc then
      for field, kind in pairs(sc) do
        local t = kind:match("^U:(.+)$")
        if t and rawget(obj, field) == nil then
          local go = core.ui_find(className .. "." .. field)
          -- scene objects referenced this way start hidden until the game activates them
          if t == "GameObject" and rawget(go, "_fresh") == nil then rawset(go, "_active", false); rawset(go, "_fresh", false) end
          rawset(obj, field, t == "GameObject" and go or go:GetComponent(t))
        end
      end
    end
    c = rawget(c, "super")
  end
end

-- GameObject.Find(name): persistent named objects whose state the UI renders
core.ui_objects = {}
core.ui_defaults = {
  LoginShortCut = { CanvasGroup = { alpha = 0, interactable = false, blocksRaycasts = false } },
  -- horror day 4 desktop, hidden until Scenario_horror_day4_day shows it
  HakkyoShortCutParent = { CanvasGroup = { alpha = 0, interactable = false, blocksRaycasts = false } },
}
-- scene objects that start inactive until the story activates them
core.ui_inactive = { liveend = true }
-- Transform of a named scene object: Find(child) reaches the named child object, gameObject the
-- owner; anything else is absorbed (positions, tweens)
local TransformT = {}
TransformT.__index = function(t, k)
  if k == "gameObject" then return rawget(t, "_go") end
  return TransformT[k] or NULL
end
function TransformT:Find(child) return core.ui_find(child).transform end
function TransformT:GetChild() return NULL end

function core.ui_find(name)
  local o = core.ui_objects[name]
  if not o then
    o = GameObject.new(name)
    rawset(o, "_transform", setmetatable({ _go = o }, TransformT))
    if core.ui_inactive[name] then rawset(o, "_active", false) end
    core.ui_objects[name] = o
  end
  return o
end
function core.ui_state(name, comp)
  return core.ui_find(name):GetComponent(comp or "CanvasGroup")
end
function GameObject:AddComponent(t) return NULL end
function GameObject.Find(name) return core.ui_find and core.ui_find(name) or NULL end
function GameObject:CompareTag() return false end

-- MonoBehaviour base for every transpiled component
local MB = setmetatable({ __name = "MonoBehaviour", __getters = {}, __setters = {} }, { __index = ObjectBase })
classes.MonoBehaviour = MB
classes.Behaviour = MB
classes.Component = MB
classes.ScriptableObject = MB
classes.UIBehaviour = MB
MB.__mt = { __index = MB }
MB.__getters.gameObject = function(self)
  local go = rawget(self, "_go")
  if not go then go = GameObject.new(rawget(self, "__name")); go._components[rawget(self, "__name") or ""] = self; rawset(self, "_go", go) end
  return go
end
MB.__getters.transform = function() return NULL end
MB.__getters.enabled = function(self) local v = rawget(self, "_enabled"); return v ~= false end
MB.__setters.enabled = function(self, v) rawset(self, "_enabled", v) end
MB.__getters.name = function(self) return rawget(self, "__name") or "" end
function MB:GetComponent(t)
  if core.components and core.components[t] then return core.components[t] end
  if t and classes[t] and rawget(classes[t], "__singleton") then return classes[t] end
  return NULL
end
MB.GetComponentInChildren = MB.GetComponent
MB.GetComponentInParent = MB.GetComponent
function MB:GetComponents() return List.new() end
function MB:StartCoroutine() return NULL end
function MB:StopCoroutine() end
function MB:StopAllCoroutines() end
function MB:Invoke(name, delay)
  local s = self
  spawn(function() core.wait_ms((delay or 0) * 1000); s[name](s) end)
end
function MB:Awake() end
function MB:Start() end

-- UnityEngine.Object statics
local UObject = setmetatable({ __name = "Object" }, { __index = ObjectBase })
classes.Object = UObject
function UObject.Instantiate(prefab) return core.ui_instantiate and core.ui_instantiate(prefab) or NULL end
function UObject.Destroy(obj) if type(obj) == "table" and obj ~= NULL and obj.__destroy then obj:__destroy() end end
UObject.DestroyImmediate = UObject.Destroy
function UObject.FindObjectOfType(t) local c = classes[t]; return (c and c.__singleton) and c or NULL end
function UObject.FindObjectsOfType() return List.new() end
function UObject.FindObjectsByType() return List.new() end
function UObject.DontDestroyOnLoad() end
MB.Instantiate = UObject.Instantiate
MB.Destroy = UObject.Destroy
MB.FindObjectOfType = UObject.FindObjectOfType
MB.DontDestroyOnLoad = UObject.DontDestroyOnLoad

-- ------------------------------------------------------------------ math & values
local function vec_mt(name, fields)
  local V = { __name = name }
  V.__index = V
  V.__add = function(a, b) local r = {} for _, f in ipairs(fields) do r[f] = a[f] + b[f] end return setmetatable(r, V) end
  V.__sub = function(a, b) local r = {} for _, f in ipairs(fields) do r[f] = a[f] - b[f] end return setmetatable(r, V) end
  V.__mul = function(a, b)
    if type(a) == "number" then a, b = b, a end
    local r = {} for _, f in ipairs(fields) do r[f] = a[f] * b end return setmetatable(r, V)
  end
  V.__eq = function(a, b) for _, f in ipairs(fields) do if a[f] ~= b[f] then return false end end return true end
  V.new = function(...) local r = {} for i, f in ipairs(fields) do r[f] = select(i, ...) or 0 end return setmetatable(r, V) end
  classes[name] = V
  return V
end
local V2 = vec_mt("Vector2", { "x", "y" })
local V3 = vec_mt("Vector3", { "x", "y", "z" })
vec_mt("Vector4", { "x", "y", "z", "w" })
V2.zero, V2.one = V2.new(0, 0), V2.new(1, 1)
V3.zero, V3.one = V3.new(0, 0, 0), V3.new(1, 1, 1)
function V3.Min(a, b) return V3.new(math.min(a.x, b.x), math.min(a.y, b.y), math.min(a.z, b.z)) end
function V3.Max(a, b) return V3.new(math.max(a.x, b.x), math.max(a.y, b.y), math.max(a.z, b.z)) end
local Color = vec_mt("Color", { "r", "g", "b", "a" })
Color.white, Color.black, Color.clear = Color.new(1, 1, 1, 1), Color.new(0, 0, 0, 1), Color.new(0, 0, 0, 0)
Color.red = Color.new(1, 0, 0, 1)
classes.Color32 = Color
classes.Quaternion = { identity = {}, Euler = function() return {} end }

Mathf = {
  Max = math.max, Min = math.min, Abs = math.abs, Sqrt = math.sqrt, Sin = math.sin, Cos = math.cos,
  PI = math.pi,
  Clamp = function(v, a, b) if v < a then return a elseif v > b then return b end return v end,
  Clamp01 = function(v) return math.max(0, math.min(1, v)) end,
  CeilToInt = function(v) return math.ceil(v) end,
  FloorToInt = function(v) return math.floor(v) end,
  RoundToInt = function(v) return math.floor(v + 0.5) end,
  Round = function(v) return math.floor(v + 0.5) end,
  Floor = math.floor, Ceil = math.ceil,
  Log10 = function(v) return math.log(v, 10) end,
  Log = function(v, b) return b and math.log(v, b) or math.log(v) end,
  Pow = function(a, b) return a ^ b end,
  Lerp = function(a, b, t) t = math.max(0, math.min(1, t)); return a + (b - a) * t end,
  Sign = function(v) return v >= 0 and 1 or -1 end,
}
classes.Mathf = Mathf
Math = {
  Max = math.max, Min = math.min, Abs = math.abs, Floor = math.floor, Ceiling = math.ceil, Sqrt = math.sqrt,
  Round = function(v) return math.floor(v + 0.5) end, Pow = function(a, b) return a ^ b end,
  Clamp = Mathf.Clamp, Log10 = Mathf.Log10,
}
classes.Math = Math

-- UnityEngine.Random.Range: int version excludes max, float version includes it
Random = {
  Range = function(a, b)
    if math.type(a) == "integer" and math.type(b) == "integer" then
      if b <= a then return a end
      return math.random(a, b - 1)
    end
    return a + math.random() * (b - a)
  end,
  value = 0,
}
setmetatable(Random, { __index = function(_, k) if k == "value" then return math.random() end end })
classes.Random = Random

Debug = {
  Log = function(m) LOG("[log]", TOSTR(m)) end,
  LogError = function(m) LOG("[error]", TOSTR(m)) end,
  LogWarning = function(m) LOG("[warn]", TOSTR(m)) end,
  LogException = function(m) LOG("[exc]", TOSTR(m)) end,
}
classes.Debug = Debug

Time = setmetatable({ timeScale = 1 }, { __index = function(_, k)
  if k == "time" or k == "realtimeSinceStartup" or k == "unscaledTime" then return core.now() end
  if k == "deltaTime" or k == "unscaledDeltaTime" then return 1 / 60 end
  if k == "frameCount" then return core.sched.frame end
end })
classes.Time = Time

Int32 = { Parse = function(s) return math.tointeger(tonumber(s)) or 0 end, MaxValue = 2147483647, MinValue = -2147483648 }
function Int32.TryParse(s)
  local n = math.tointeger(tonumber(s))
  return n ~= nil, n or 0
end
classes.Int32 = Int32
Single = { IsNegativeInfinity = function(v) return v == -math.huge end, MaxValue = 3.4e38 }
classes.Single = Single
classes.Convert = { ToInt32 = function(v) return math.floor(tonumber(v) or 0) end, ToString = TOSTR }

Enum = {
  GetValues = function(t)
    local e, l = core.enums and core.enums[t] or {}, {}
    for k, v in pairs(e) do l[#l + 1] = { k, v } end
    table.sort(l, function(a, b) return a[2] < b[2] end)
    local r = List.new()
    for _, kv in ipairs(l) do r:Add(kv[1]) end
    return r
  end,
  Parse = function(t, s) return s end,
  TryParse = function(t, s)
    local e = core.enums and core.enums[t]
    if e and e[s] ~= nil then return true, s end
    return false, nil
  end,
  ToObject = function(t, n) return ENUMN(t, n) end,
  IsDefined = function(t, v) local e = core.enums[t]; return e ~= nil and e[v] ~= nil end,
}
Enum.GetNames = Enum.GetValues
classes.Enum = Enum

Application = { systemLanguage = "Spanish", dataPath = "sdmc:/3ds/needy3ds", persistentDataPath = "sdmc:/3ds/needy3ds", isEditor = false, platform = "Nintendo3DS" }
function Application.Quit() if game then game.quit = true end end
classes.Application = Application
Screen = { width = 400, height = 240, SetResolution = function() end, fullScreen = true }
classes.Screen = Screen
PlayerPrefs = { _d = {} }
function PlayerPrefs.SetString(k, v) PlayerPrefs._d[k] = v end
function PlayerPrefs.GetString(k, d) return PlayerPrefs._d[k] or d or "" end
PlayerPrefs.SetInt, PlayerPrefs.GetInt = PlayerPrefs.SetString, function(k, d) return PlayerPrefs._d[k] or d or 0 end
function PlayerPrefs.Save() end
function PlayerPrefs.HasKey(k) return PlayerPrefs._d[k] ~= nil end
classes.PlayerPrefs = PlayerPrefs
classes.SceneManager = { LoadScene = function(name) if core.on_load_scene then core.on_load_scene(name) end end }
classes.SceneManager.LoadSceneAsync = classes.SceneManager.LoadScene

-- Input: mouse queries map to the stylus
Input = setmetatable({}, { __index = function(_, k)
  local ip = core.input
  if k == "mousePosition" then return V3.new(ip and ip.tx or 0, ip and ip.ty or 0, 0) end
  return NULL
end })
function Input.GetMouseButtonDown() return core.input and core.input.tap_down or false end
function Input.GetMouseButton() return core.input and core.input.touching or false end
function Input.GetMouseButtonUp() return core.input and core.input.tap_up or false end
function Input.GetKeyDown() return false end
function Input.GetKey() return false end
classes.Input = Input
classes.KeyCode = setmetatable({}, { __index = function(_, k) return k end })

-- reflection used to create events by name: Type.GetType("ngov3.X") / Activator.CreateInstance
Type = {}
function Type.GetType(name)
  local short = tostring(name):match("([^%.]+)$")
  local C = core.resolve(short)
  if C == NULL then return nil end
  return C
end
classes.Type = Type
Activator = { CreateInstance = function(C) return NEW(C) end }
classes.Activator = Activator
classes.GC = { Collect = function() collectgarbage() end }

-- Regex: just the .NET patterns the game uses, mapped to Lua patterns
local function to_lua_pattern(p)
  local look = p:match("^%(%?<=([^)]*)%)")
  local rest = look and p:sub(#look + 6) or p
  local lp = rest:gsub("\\d", "%%d"):gsub("\\s", "%%s"):gsub("\\w", "%%w")
  return look, lp
end
Regex = {}
function Regex.Match(s, p)
  local look, lp = to_lua_pattern(p)
  local v
  if look then
    local i = s:find(look, 1, true)
    v = i and s:sub(i + #look):match("^" .. lp)
  else
    v = s:match(lp)
  end
  return { Value = v or "", Success = v ~= nil }
end
function Regex.IsMatch(s, p) return Regex.Match(s, p).Success end
function Regex.Replace(s, p, rep)
  local _, lp = to_lua_pattern(p)
  lp = lp:gsub("%*", "-")
  return (s:gsub(lp, (rep:gsub("%%", "%%%%"))))
end
classes.Regex = Regex

-- DOTween: tweens resolve instantly (the 3DS UI animates on its own)
DOTween = { To = function(getter, setter, endValue) if type(setter) == "function" then pcall(setter, endValue) end return NULL end,
            Sequence = function() return NULL end, Kill = function() end, KillAll = function() end }
classes.DOTween = DOTween
classes.DOVirtual = { DelayedCall = function(t, fn) spawn(function() core.wait_ms(t * 1000); fn() end) return NULL end,
                      Float = function(a, b, t, fn) pcall(fn, b) return NULL end }

return {}
