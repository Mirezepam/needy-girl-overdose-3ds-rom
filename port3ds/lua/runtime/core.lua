-- Core runtime for the transpiled C#: classes, C#-like collections, helper functions emitted
-- by cs2lua, coroutine scheduler (async/await) and a lazy global class loader.

local core = {}
local log_once = {}

function LOG(...)
  local parts = {}
  for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
  local line = table.concat(parts, " ")
  if core.logfile then core.logfile:write(line, "\n"); core.logfile:flush() end
end

function LOG_ONCE(key, ...)
  if log_once[key] then return end
  log_once[key] = true
  LOG(...)
end

-- ------------------------------------------------------------------ null object
-- Absorbs any access/call into Unity APIs that the 3DS runtime does not implement.
local Null = {}
local null_mt = {}
NULL = setmetatable(Null, null_mt)
-- tween callbacks hanging off missing Unity objects still run (DOTween OnComplete/AppendCallback)
local CALLBACK_KEYS = { OnComplete = 0.8, AppendCallback = 0.8, OnStepComplete = 0.8, OnKill = 0.8, InsertCallback = 0.8, PrependCallback = 0 }
local cb_funcs = {}
for k, delay in pairs(CALLBACK_KEYS) do
  cb_funcs[k] = function(_, a, b)
    local fn = type(a) == "function" and a or (type(b) == "function" and b or nil)
    if fn then
      spawn(function() core.wait_ms(delay * 1000); fn() end)
    end
    return NULL
  end
end
null_mt.__index = function(_, k)
  if k == "Count" or k == "childCount" or k == "Length" then return 0 end
  local cb = cb_funcs[k]
  if cb then return cb end
  return NULL
end
null_mt.__newindex = function() end
null_mt.__call = function() return NULL end
null_mt.__concat = function(a, b) return (a == NULL and "" or tostring(a)) .. (b == NULL and "" or tostring(b)) end
null_mt.__len = function() return 0 end
null_mt.__tostring = function() return "" end
null_mt.__unm = function() return 0 end
for _, op in ipairs({ "__add", "__sub", "__mul", "__div", "__mod", "__idiv" }) do
  null_mt[op] = function(a, b) return (a == NULL) and (type(b) == "number" and b or 0) or a end
end
null_mt.__lt = function() return false end
null_mt.__le = function() return false end

function IS_CANCEL(e) return type(e) == "table" and e.canceled == true end
function LOG_ERROR(e) if not IS_CANCEL(e) then LOG("[error] caught:", tostring(e)) end end

function TODO(code) LOG_ONCE("todo:" .. tostring(code), "TODO stmt:", code) end
function TODO_EXPR(code) LOG_ONCE("todoe:" .. tostring(code), "TODO expr:", code); return NULL end

-- ------------------------------------------------------------------ classes
local classes = {}
core.classes = classes
local gen_index = {}
local loading = {}

local function make_instance_mt(C)
  local mt = {}
  mt.__index = function(t, k)
    local c = C
    while c do
      local g = rawget(c, "__getters")
      if g then
        local f = g[k]
        if f then return f(t) end
      end
      c = rawget(c, "super")
    end
    return C[k]
  end
  mt.__newindex = function(t, k, v)
    local c = C
    while c do
      local s = rawget(c, "__setters")
      if s then
        local f = s[k]
        if f then return f(t, v) end
      end
      c = rawget(c, "super")
    end
    rawset(t, k, v)
  end
  mt.__tostring = function(t)
    local f = C.ToString
    if f and f ~= core.default_tostring then return f(t) end
    return C.__name
  end
  mt.__name = C.__name
  return mt
end

function class(name, baseName)
  local C = { __name = name, __getters = {}, __setters = {} }
  local base
  if baseName and baseName ~= "Object" and baseName ~= name then
    base = core.resolve(baseName)
    if base == NULL then base = nil end
  end
  C.super = base
  setmetatable(C, {
    __index = function(t, k)
      -- property getters also apply when the class table acts as a singleton instance
      local c = t
      while c do
        local g = rawget(c, "__getters")
        if g and g[k] then return g[k](t) end
        c = rawget(c, "super")
      end
      if base then return base[k] end
      return core.ObjectBase and core.ObjectBase[k]
    end,
    -- singletons: the class table doubles as the instance, so getters/setters apply to it too
    __newindex = function(t, k, v)
      local c = t
      while c do
        local s = rawget(c, "__setters")
        if s and s[k] then return s[k](t, v) end
        c = rawget(c, "super")
      end
      rawset(t, k, v)
    end,
    __tostring = function() return name end,
  })
  C.__mt = make_instance_mt(C)
  classes[name] = C
  return C
end

-- PC-only UI helpers (gamepad guides, keyboard shortcuts, debug panels): any call is a no-op
local STUBS = {
  ControllerGuideManager = true, ShortcutInputManager = true, VibrationInputManager = true,
  LoginShortcutInputManager = true, EndingShortcutInputManager = true, GraphManager = true,
  SliderManager = true, DebugManager = true, TaskManagerManager = true, ChachedWindowStore = true,
  SwitchInputModule = true, PlayStationInputDisable = true, MouseCursor = true, LogWriter = true,
  NintendoSaveManager = true, TestTrophyUnlock = true, TropyManager = true, Addressables = true,
}
core.STUBS = STUBS

function core.resolve(name)
  local c = classes[name]
  if c then return c end
  if STUBS[name] then
    c = setmetatable({ __name = name }, { __index = function() return NULL end })
    classes[name] = c
    return c
  end
  if loading[name] then return NULL end
  loading[name] = true
  local mod
  -- hand-written overrides first, then transpiled code
  for _, prefix in ipairs({ "override.", "runtime.unity." }) do
    local ok, res = pcall(require, prefix .. name)
    if ok then mod = res; break end
    if not tostring(res):find("module '" .. prefix .. name .. "' not found", 1, true) then error(res, 0) end
  end
  if not mod and gen_index[name] then mod = require(gen_index[name]) end
  loading[name] = nil
  if mod then
    classes[name] = mod
    if core.after_load then core.after_load(mod) end
    return mod
  end
  LOG_ONCE("missing:" .. name, "missing class:", name)
  return NULL
end

-- unknown globals resolve to classes (loaded lazily) or the null object
setmetatable(_G, {
  __index = function(_, k)
    if type(k) ~= "string" or k:sub(1, 1) == "_" then return nil end
    local c = core.resolve(k)
    rawset(_G, k, c)
    return c
  end,
})

function core.load_index(idx) gen_index = idx end

function NEW(typeName, ctorIdx, ...)
  local C = type(typeName) == "table" and typeName or core.resolve(typeName)
  if C == NULL then return NULL end
  if rawget(C, "new") then return C.new(...) end
  local obj = setmetatable({}, C.__mt)
  if obj.__fields then obj:__fields() end
  if ctorIdx and obj["__ctor_" .. ctorIdx] then
    obj["__ctor_" .. ctorIdx](obj, ...)
  elseif ctorIdx then
    -- implicit constructor
  elseif obj.__ctor_1 and select("#", ...) > 0 then
    obj:__ctor_1(...)
  end
  return obj
end

function INIT(obj, fields)
  for k, v in pairs(fields) do obj[k] = v end
  return obj
end

function IS(obj, typeName)
  if obj == nil then return false end
  if type(obj) ~= "table" then
    return (typeName == "string" and type(obj) == "string") or (typeName == "int" and math.type(obj) == "integer")
  end
  local mt = getmetatable(obj)
  local C = mt and classes[mt.__name]
  while C do
    if C.__name == typeName then return true end
    C = rawget(C, "super")
  end
  return false
end

-- ------------------------------------------------------------------ C# helpers emitted by cs2lua
local ENUMS
function core.set_enums(e) ENUMS = e end

function ENUMV(enumName, v)
  if type(v) == "number" then return v end
  local e = ENUMS[enumName]
  return e and e[v] or 0
end

function ENUMN(enumName, n)
  local e = ENUMS[enumName]
  if e then
    for k, v in pairs(e) do
      if v == n then return k end
    end
  end
  return n
end

function TOSTR(v)
  if v == nil then return "" end
  if v == true then return "True" end
  if v == false then return "False" end
  if math.type(v) == "float" and v == math.floor(v) and math.abs(v) < 1e15 then return string.format("%d", v) end
  return tostring(v)
end

function CONCAT(a, b) return TOSTR(a) .. TOSTR(b) end

function FMT(v, fmt)
  if type(v) == "number" then
    if fmt:match("^N0") or fmt == "#,0" or fmt == "#,##0" then
      local s = string.format("%d", math.floor(v))
      local r = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
      return (r:gsub("^(-?),", "%1"))
    end
    local d = fmt:match("^D(%d+)")
    if d then return string.format("%0" .. d .. "d", math.floor(v)) end
    local f = fmt:match("^[FN](%d+)")
    if f then return string.format("%." .. f .. "f", v) end
  end
  return TOSTR(v)
end

function TRUNC(x) return x >= 0 and math.floor(x) or math.ceil(x) end
function IDIV(a, b) return TRUNC(a / b) end
function MOD(a, b) return math.fmod(a, b) end
function nz(a, b) if a == nil or a == NULL then return b end return a end
function BITAND(a, b) return a & b end
function BITOR(a, b) return a | b end
function BITXOR(a, b) return a ~ b end
function BITNOT(a) return ~a end

function IDX(o, i)
  if o == nil or o == NULL then return NULL end
  if type(o) == "string" then return o:sub(i + 1, i + 1) end
  local get = o.__idx
  if get then return get(o, i) end
  return o[i]
end

function SETIDX(o, i, v)
  local set = o.__setidx
  if set then return set(o, i, v) end
  o[i] = v
end

function EACH(o)
  if o == nil or o == NULL then return function() end end
  if o.__each then return o:__each() end
  return pairs(o)
end

-- ------------------------------------------------------------------ List / Dictionary (0-based like C#)
local List = { __name = "List" }
List.__index = function(t, k)
  if k == "Count" or k == "Length" then return t.n end
  return List[k]
end
classes.List = List
classes.ReactiveCollection = nil

function List.new(...)
  local l = setmetatable({ n = 0, items = {} }, List)
  local first = ...
  if type(first) == "table" and first ~= NULL and first.__each then
    for _, v in first:__each() do l:Add(v) end
  end
  return l
end

function LIST(...)
  local l = setmetatable({ n = select("#", ...), items = { ... } }, List)
  return l
end

function LISTT(t)
  return setmetatable({ n = #t, items = t }, List)
end

function DICTT(t)
  local d = core.Dict.new()
  for _, kv in ipairs(t) do d:Add(kv:__idx(0), kv:__idx(1)) end
  return d
end

function ADDALL(obj, t)
  for _, v in ipairs(t) do obj:Add(v) end
  return obj
end

function ARRAY(n)
  local l = setmetatable({ n = n, items = {} }, List)
  return l
end

function List:__idx(i) return self.items[i + 1] end
function List:__setidx(i, v) self.items[i + 1] = v; if i + 1 > self.n then self.n = i + 1 end end
function List:__each()
  local i = 0
  return function()
    i = i + 1
    if i <= self.n then return i - 1, self.items[i] end
  end
end
function List:Add(v) self.n = self.n + 1; self.items[self.n] = v end
function List:AddRange(o) for _, v in EACH(o) do self:Add(v) end end
function List:Insert(i, v) table.insert(self.items, i + 1, v); self.n = self.n + 1 end
function List:InsertRange(i, o)
  local k = i
  for _, v in EACH(o) do self:Insert(k, v); k = k + 1 end
end
function List:RemoveAt(i) table.remove(self.items, i + 1); self.n = self.n - 1 end
function List:Remove(v)
  for i = 1, self.n do
    if self.items[i] == v then table.remove(self.items, i); self.n = self.n - 1; return true end
  end
  return false
end
function List:RemoveAll(pred)
  local kept, removed = {}, 0
  for i = 1, self.n do
    if pred(self.items[i]) then removed = removed + 1 else kept[#kept + 1] = self.items[i] end
  end
  self.items, self.n = kept, #kept
  return removed
end
function List:Clear() self.items = {}; self.n = 0 end
function List:Contains(v) for i = 1, self.n do if self.items[i] == v then return true end end return false end
function List:IndexOf(v) for i = 1, self.n do if self.items[i] == v then return i - 1 end end return -1 end
function List:Exists(pred) for i = 1, self.n do if pred(self.items[i]) then return true end end return false end
function List:Any(pred)
  if not pred then return self.n > 0 end
  return self:Exists(pred)
end
function List:All(pred) for i = 1, self.n do if not pred(self.items[i]) then return false end end return true end
function List:Find(pred) for i = 1, self.n do if pred(self.items[i]) then return self.items[i] end end return nil end
function List:FindIndex(pred) for i = 1, self.n do if pred(self.items[i]) then return i - 1 end end return -1 end
function List:FindAll(pred) return self:Where(pred) end
function List:Where(pred)
  local r = List.new()
  for i = 1, self.n do if pred(self.items[i], i - 1) then r:Add(self.items[i]) end end
  return r
end
function List:Select(fn)
  local r = List.new()
  for i = 1, self.n do r:Add(fn(self.items[i], i - 1)) end
  return r
end
function List:ToList() local r = List.new(); for i = 1, self.n do r:Add(self.items[i]) end return r end
List.ToArray = List.ToList
function List:Distinct()
  local r, seen = List.new(), {}
  for i = 1, self.n do
    local v = self.items[i]
    if not seen[v] then seen[v] = true; r:Add(v) end
  end
  return r
end
function List:First(pred)
  for i = 1, self.n do if not pred or pred(self.items[i]) then return self.items[i] end end
  error("Sequence contains no matching element")
end
function List:FirstOrDefault(pred)
  for i = 1, self.n do if not pred or pred(self.items[i]) then return self.items[i] end end
  return nil
end
function List:Last() return self.items[self.n] end
function List:LastOrDefault() return self.items[self.n] end
function List:TakeLast(k)
  local r = List.new()
  for i = math.max(1, self.n - k + 1), self.n do r:Add(self.items[i]) end
  return r
end
function List:Take(k) local r = List.new(); for i = 1, math.min(k, self.n) do r:Add(self.items[i]) end return r end
function List:Skip(k) local r = List.new(); for i = k + 1, self.n do r:Add(self.items[i]) end return r end
function List:GetRange(s, c) local r = List.new(); for i = s + 1, math.min(self.n, s + c) do r:Add(self.items[i]) end return r end
function List:Sum(fn) local s = 0; for i = 1, self.n do s = s + (fn and fn(self.items[i]) or self.items[i]) end return s end
function List:Max(fn) local m; for i = 1, self.n do local v = fn and fn(self.items[i]) or self.items[i]; if not m or v > m then m = v end end return m end
function List:Min(fn) local m; for i = 1, self.n do local v = fn and fn(self.items[i]) or self.items[i]; if not m or v < m then m = v end end return m end
function List:CountWhere(fn) local c = 0; for i = 1, self.n do if fn(self.items[i]) then c = c + 1 end end return c end
function List:Reverse() local r = {}; for i = self.n, 1, -1 do r[#r + 1] = self.items[i] end self.items = r end
function List:Sort(cmp)
  table.sort(self.items, cmp and function(a, b) return cmp(a, b) < 0 end or nil)
end
function List:OrderBy(fn)
  local r = self:ToList()
  table.sort(r.items, function(a, b) return fn(a) < fn(b) end)
  return r
end
function List:OrderByDescending(fn)
  local r = self:ToList()
  table.sort(r.items, function(a, b) return fn(a) > fn(b) end)
  return r
end
function List:ForEach(fn) for i = 1, self.n do fn(self.items[i]) end end
function List:GetValue(i) return self.items[i + 1] end
function List:Except(o)
  local ex = {}
  for _, v in EACH(o) do ex[v] = true end
  return self:Where(function(v) return not ex[v] end)
end
function List:Concat(o) local r = self:ToList(); for _, v in EACH(o) do r:Add(v) end return r end
function List:Append(v) local r = self:ToList(); r:Add(v); return r end
function List:ElementAt(i) return self.items[i + 1] end
List.ElementAtOrDefault = List.ElementAt
function List:FindLast(pred) for i = self.n, 1, -1 do if pred(self.items[i]) then return self.items[i] end end end
function List:RemoveRange(i, c) for _ = 1, c do table.remove(self.items, i + 1) end self.n = math.max(0, self.n - c) end
function List:Cast() return self end
List.OfType = List.Cast
function List:Zip(o, fn)
  local r = List.new()
  for i = 1, math.min(self.n, o.n or 0) do r:Add(fn and fn(self.items[i], o.items[i]) or { self.items[i], o.items[i] }) end
  return r
end
function LCOUNT(o, pred)
  if o == nil or o == NULL then return 0 end
  if not pred then return o.Count or 0 end
  local c = 0
  for _, v in EACH(o) do if pred(v) then c = c + 1 end end
  return c
end

-- StringBuilder
local SB = { __name = "StringBuilder" }
SB.__index = function(t, k) if k == "Length" then return #table.concat(t.parts) end return SB[k] end
classes.StringBuilder = SB
function SB.new(s) return setmetatable({ parts = { s or "" } }, SB) end
function SB:Append(v) self.parts[#self.parts + 1] = TOSTR(v); return self end
function SB:AppendLine(v) self.parts[#self.parts + 1] = TOSTR(v) .. "\n"; return self end
function SB:Clear() self.parts = {}; return self end
function SB:ToString() return table.concat(self.parts) end
SB.__tostring = SB.ToString

function List:Shuffle()
  for i = self.n, 2, -1 do
    local j = math.random(i)
    self.items[i], self.items[j] = self.items[j], self.items[i]
  end
  return self
end

local Dict = { __name = "Dictionary" }
Dict.__index = function(t, k)
  if k == "Count" then local c = 0; for _ in pairs(t.map) do c = c + 1 end return c end
  if k == "Keys" then local r = List.new(); for _, key in ipairs(t.order) do if t.map[key] ~= nil then r:Add(key) end end return r end
  if k == "Values" then local r = List.new(); for _, key in ipairs(t.order) do if t.map[key] ~= nil then r:Add(t.map[key]) end end return r end
  return Dict[k]
end
classes.Dictionary = Dict
function Dict.new() return setmetatable({ map = {}, order = {} }, Dict) end
function DICT(...)
  local d = Dict.new()
  for i = 1, select("#", ...) do
    local kv = select(i, ...)
    d:Add(kv:__idx(0), kv:__idx(1))
  end
  return d
end
function Dict:__idx(k) return self.map[k] end
function Dict:__setidx(k, v) if self.map[k] == nil then self.order[#self.order + 1] = k end self.map[k] = v end
function Dict:Add(k, v) self:__setidx(k, v) end
function Dict:ContainsKey(k) return self.map[k] ~= nil end
function Dict:TryGetValue(k) local v = self.map[k]; return v ~= nil, v end
function Dict:Remove(k) self.map[k] = nil end
function Dict:Clear() self.map, self.order = {}, {} end
function Dict:__each()
  local i = 0
  return function()
    while true do
      i = i + 1
      local k = self.order[i]
      if k == nil then return nil end
      if self.map[k] ~= nil then return k, { Key = k, Value = self.map[k] } end
    end
  end
end

-- Queue<T>
local Queue = { __name = "Queue" }
Queue.__index = function(t, k)
  if k == "Count" then return t.tail - t.head end
  return Queue[k]
end
classes.Queue = Queue
function Queue.new() return setmetatable({ head = 0, tail = 0, items = {} }, Queue) end
function Queue:Enqueue(v) self.items[self.tail] = v; self.tail = self.tail + 1 end
function Queue:Dequeue()
  if self.tail == self.head then error("Queue empty") end
  local v = self.items[self.head]
  self.items[self.head] = nil
  self.head = self.head + 1
  return v
end
function Queue:Peek() return self.items[self.head] end
function Queue:Clear() self.head, self.tail, self.items = 0, 0, {} end
function Queue:Contains(v) for i = self.head, self.tail - 1 do if self.items[i] == v then return true end end return false end
function Queue:__each()
  local i = self.head - 1
  return function() i = i + 1; if i < self.tail then return i, self.items[i] end end
end
function Queue:ToList() local l = List.new(); for i = self.head, self.tail - 1 do l:Add(self.items[i]) end return l end
classes.Stack = nil

-- string helpers (STR.X(s, ...))
STR = {}
function STR.StartsWith(s, p) return s:sub(1, #p) == p end
function STR.EndsWith(s, p) return p == "" or s:sub(-#p) == p end
function STR.Contains(s, p) return s:find(p, 1, true) ~= nil end
function STR.Replace(s, a, b) return (s:gsub(a:gsub("%p", "%%%0"), (b:gsub("%%", "%%%%")))) end
function STR.Length(s) return utf8.len(s) or #s end
function STR.IsNullOrEmpty(s) return s == nil or s == "" end
function STR.IsNullOrWhiteSpace(s) return s == nil or s:match("^%s*$") ~= nil end
function STR.Trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function STR.ToUpper(s) return s:upper() end
function STR.ToLower(s) return s:lower() end
function STR.Substring(s, i, n)
  local a = utf8.offset(s, i + 1) or (#s + 1)
  if not n then return s:sub(a) end
  local b = utf8.offset(s, i + n + 1) or (#s + 1)
  return s:sub(a, b - 1)
end
function STR.Split(s, sep, opt)
  if type(sep) == "table" then sep = sep:__idx(0) end
  local noEmpty = opt == "RemoveEmptyEntries"
  local r, start = List.new(), 1
  local function add(part) if not (noEmpty and part == "") then r:Add(part) end end
  while true do
    local a, b = s:find(sep, start, true)
    if not a then add(s:sub(start)); break end
    add(s:sub(start, a - 1))
    start = b + 1
  end
  return r
end
function STR.Format(fmt, ...)
  local args = { ... }
  return (fmt:gsub("{(%d+)(:?[^}]*)}", function(i, f)
    local v = args[tonumber(i) + 1]
    if f ~= "" then return FMT(v, f:sub(2)) end
    return TOSTR(v)
  end))
end
function STR.Join(sep, list)
  local parts = {}
  for _, v in EACH(list) do parts[#parts + 1] = TOSTR(v) end
  return table.concat(parts, sep)
end
function STR.Concat(...) local p = {}; for i = 1, select("#", ...) do p[i] = TOSTR((select(i, ...))) end return table.concat(p) end
function STR.Equals(a, b) return a == b end
function STR.PadLeft(s, n, c) c = c or " "; return string.rep(c, n - #s) .. s end

-- ------------------------------------------------------------------ scheduler (async/await)
local sched = { tasks = {}, now = 0, frame = 0 }
core.sched = sched

function core.now() return sched.now end

-- Like Unity, an exception inside an async task or Rx callback is logged and the game goes on
-- (the C# game relies on this: some of its callbacks throw in edge cases).
core.error_count = 0
local function resume(co, ...)
  local ok, err = coroutine.resume(co, ...)
  if not ok then
    if type(err) == "table" and err.canceled then return end  -- OperationCanceledException
    core.error_count = core.error_count + 1
    LOG("[error] task:", debug.traceback(co, tostring(err)))
    if core.strict then error(debug.traceback(co, tostring(err)), 0) end
  end
end

-- runs fn immediately until its first await (C# semantics for un-awaited async calls)
function spawn(fn, ...)
  local co = coroutine.create(fn)
  resume(co, ...)
  return co
end

local function in_coroutine()
  local _, main = coroutine.running()
  return not main
end
core.in_coroutine = in_coroutine

-- yields the running coroutine until cond() returns true
function core.wait_until(cond)
  if cond() then return end
  if not in_coroutine() then
    LOG_ONCE("waitmain:" .. debug.traceback("", 2):sub(1, 200), "wait outside coroutine", debug.traceback("", 2))
    return
  end
  local co = coroutine.running()
  sched.tasks[#sched.tasks + 1] = { co = co, cond = cond }
  coroutine.yield()
end

function core.wait_ms(ms, token)
  local t = sched.now + (ms or 0) / 1000
  core.wait_until(function()
    if token and token ~= NULL and token.IsCancellationRequested then return true end
    return sched.now >= t
  end)
  if token and token ~= NULL and token.IsCancellationRequested then
    if core.debug_cancel then LOG("[cancel]", debug.traceback("", 2)) end
    error({ canceled = true }, 0)
  end
end

function core.wait_frames(n)
  local target = sched.frame + (n or 1)
  core.wait_until(function() return sched.frame >= target end)
end

local pollers = {}
core.pollers = pollers

function core.update(dt)
  -- fast-forward (skip text): game time runs 6x faster
  if core.fast then dt = dt * 6 end
  sched.now = sched.now + dt
  sched.frame = sched.frame + 1
  for i = #pollers, 1, -1 do
    local p = pollers[i]
    if p.dead then table.remove(pollers, i) else p.fn() end
  end
  local tasks = sched.tasks
  sched.tasks = {}
  for _, t in ipairs(tasks) do
    if t.cond() then
      resume(t.co)
    else
      sched.tasks[#sched.tasks + 1] = t
    end
  end
end

-- per-frame callback; returns a handle with :Dispose()
local PollHandle = {}
PollHandle.__index = PollHandle
function PollHandle:Dispose() self.p.dead = true end
function PollHandle:AddTo(target)
  if type(target) == "table" and target ~= NULL and target.__composite then target:Add(self) end
  return self
end
function core.poll(fn)
  local p = { fn = fn }
  pollers[#pollers + 1] = p
  return setmetatable({ p = p }, PollHandle)
end

core.List = List
core.Dict = Dict
core.default_tostring = nil
return core
