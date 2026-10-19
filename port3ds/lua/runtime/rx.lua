-- Minimal UniRx + UniTask for the transpiled scripts.
-- Observables are push-based; subscriber callbacks run through spawn() so async lambdas
-- behave like C#: they run synchronously until their first await.
local core = require("runtime.core")
local List = core.List
local classes = core.classes

-- ------------------------------------------------------------------ disposables
local Disposable = {}
Disposable.__index = Disposable
function Disposable.new(fn) return setmetatable({ fn = fn }, Disposable) end
function Disposable:Dispose()
  if self.fn then local f = self.fn; self.fn = nil; f() end
end
function Disposable:AddTo(target)
  if type(target) == "table" and target ~= NULL and target.__composite then target:Add(self) end
  return self
end

local Composite = { __composite = true, __name = "CompositeDisposable" }
Composite.__index = Composite
function Composite.new() return setmetatable({ items = {}, __composite = true }, Composite) end
function Composite:Add(d) self.items[#self.items + 1] = d end
function Composite:Clear()
  local items = self.items
  self.items = {}
  for _, d in ipairs(items) do d:Dispose() end
end
Composite.Dispose = Composite.Clear
classes.CompositeDisposable = Composite

local Single = { __name = "SingleAssignmentDisposable" }
Single.__index = Single
function Single.new() return setmetatable({}, Single) end
function Single:Dispose() end
classes.SingleAssignmentDisposable = Single

-- ------------------------------------------------------------------ observables
local Observable = { __name = "Observable" }
Observable.__index = Observable
classes.Observable = Observable

-- subscribe(observer) -> disposable; observer = {next=fn, completed=fn}
local function obs(subscribe) return setmetatable({ _subscribe = subscribe }, Observable) end
core.observable = obs

function Observable:Subscribe(onNext, onError, onCompleted)
  if type(onNext) ~= "function" then onNext = function() end end
  return self._subscribe({
    next = function(v) spawn(onNext, v) end,
    completed = function() if type(onCompleted) == "function" then onCompleted() end end,
  })
end

function Observable:Where(pred)
  local src = self
  return obs(function(o) return src._subscribe({ next = function(v) if pred(v) then o.next(v) end end, completed = o.completed }) end)
end

function Observable:Select(fn)
  local src = self
  return obs(function(o) return src._subscribe({ next = function(v) o.next(fn(v)) end, completed = o.completed }) end)
end

function Observable:Take(n)
  local src = self
  return obs(function(o)
    local count, d = 0, nil
    local done = false
    d = src._subscribe({
      next = function(v)
        if done then return end
        count = count + 1
        if count >= n then done = true end
        o.next(v)
        if done then o.completed(); if d then d:Dispose() end end
      end,
      completed = o.completed,
    })
    if done then d:Dispose() end
    return d
  end)
end
Observable.First = function(self) return self:Take(1) end

function Observable:Skip(n)
  local src = self
  return obs(function(o)
    local count = 0
    return src._subscribe({ next = function(v) count = count + 1; if count > n then o.next(v) end end, completed = o.completed })
  end)
end

-- ReactiveProperty.SkipLatestValueOnSubscribe: drop what is replayed while subscribing
function Observable:SkipLatestValueOnSubscribe()
  local src = self
  return obs(function(o)
    local subscribing = true
    local d = src._subscribe({ next = function(v) if not subscribing then o.next(v) end end, completed = o.completed })
    subscribing = false
    return d
  end)
end

function Observable:DistinctUntilChanged()
  local src = self
  return obs(function(o)
    local has, last = false, nil
    return src._subscribe({
      next = function(v) if not has or v ~= last then has, last = true, v; o.next(v) end end,
      completed = o.completed,
    })
  end)
end

function Observable:Delay(span)
  local src = self
  return obs(function(o)
    return src._subscribe({ next = function(v) spawn(function() core.wait_ms(span.ms); o.next(v) end) end, completed = o.completed })
  end)
end

function Observable:Scan(a, b)
  local src = self
  local seed, fn = a, b
  if b == nil then seed, fn = nil, a end
  return obs(function(o)
    local acc, has = seed, seed ~= nil
    return src._subscribe({ next = function(v)
      if has then acc = fn(acc, v) else acc, has = v, true end
      o.next(acc)
    end, completed = o.completed })
  end)
end

function Observable:ThrottleFirst(span)
  local src = self
  return obs(function(o)
    local last = -1e9
    return src._subscribe({ next = function(v)
      if core.now() - last >= span.ms / 1000 then last = core.now(); o.next(v) end
    end, completed = o.completed })
  end)
end
function Observable:TakeUntilDestroy() return self end
function Observable:ObserveEveryValueChanged(fn) return core.every_value_changed(self, fn) end
function Observable:Forget() end

function Observable:TakeWhile(pred)
  local src = self
  return obs(function(o)
    local d, done
    d = src._subscribe({ next = function(v)
      if done then return end
      if pred(v) then o.next(v) else done = true; o.completed(); if d then d:Dispose() end end
    end, completed = o.completed })
    return d
  end)
end

function Observable:TakeUntil(other)
  local src = self
  return obs(function(o)
    local stop = false
    local d1 = src._subscribe({ next = function(v) if not stop then o.next(v) end end, completed = o.completed })
    local d2 = other._subscribe and other._subscribe({ next = function() stop = true; d1:Dispose() end, completed = function() end })
    return Disposable.new(function() d1:Dispose(); if d2 then d2:Dispose() end end)
  end)
end

function Observable:SelectMany(fn)
  local src = self
  return obs(function(o)
    return src._subscribe({ next = function(v)
      local r = fn(v)
      if type(r) == "table" and r._subscribe then r._subscribe({ next = o.next, completed = function() end })
      else o.next(r) end
    end, completed = o.completed })
  end)
end

local function merge(list)
  return obs(function(o)
    local ds = {}
    for _, s in ipairs(list) do
      if type(s) == "table" and s._subscribe then ds[#ds + 1] = s._subscribe({ next = o.next, completed = function() end }) end
    end
    return Disposable.new(function() for _, d in ipairs(ds) do d:Dispose() end end)
  end)
end
function Observable:Merge(...)
  if getmetatable(self) == nil or self == Observable then return merge({ ... }) end
  return merge({ self, ... })
end
Observable.Concat = Observable.Merge
function Observable:Zip(other) return self:Merge(other) end

function Observable:Distinct()
  local src = self
  return obs(function(o)
    local seen = {}
    return src._subscribe({ next = function(v) if not seen[v] then seen[v] = true; o.next(v) end end, completed = o.completed })
  end)
end

function Observable:First(pred) if pred then return self:Where(pred):Take(1) end return self:Take(1) end
function Observable:Last() return self end
function Observable:FirstOrDefault(pred) return self:First(pred) end

-- re-subscribes every time the source completes (used with First/Take to restart counters)
function Observable:Repeat()
  local src = self
  return obs(function(o)
    local alive, cur = true, nil
    local function sub()
      cur = src._subscribe({ next = o.next, completed = function()
        if alive then spawn(function() core.wait_frames(1); if alive then sub() end end) end
      end })
    end
    sub()
    return Disposable.new(function() alive = false; if cur then cur:Dispose() end end)
  end)
end
Observable.RepeatUntilDestroy = Observable.Repeat
Observable.RepeatSafe = Observable.Repeat
function Observable:Share() return self end
function Observable:AsObservable() return self end
function Observable:AsUnitObservable() return self:Select(function() return classes.Unit.Default end) end

function Observable:Pairwise()
  local src = self
  return obs(function(o)
    local has, prev = false, nil
    return src._subscribe({ next = function(v)
      if has then o.next({ Previous = prev, Current = v }) end
      has, prev = true, v
    end, completed = o.completed })
  end)
end

function Observable:Throttle(span)
  local src = self
  return obs(function(o)
    local token = 0
    return src._subscribe({ next = function(v)
      token = token + 1
      local mine = token
      spawn(function() core.wait_ms(span.ms); if mine == token then o.next(v) end end)
    end, completed = o.completed })
  end)
end

function Observable:Buffer(n)
  local src = self
  return obs(function(o)
    local buf = List.new()
    return src._subscribe({ next = function(v)
      buf:Add(v)
      if buf.n >= n then local b = buf; buf = List.new(); o.next(b) end
    end, completed = o.completed })
  end)
end

function Observable:AddTo(target) return self end
function Observable:ToUniTask() return nil end

-- Subject
local Subject = setmetatable({ __name = "Subject" }, { __index = Observable })
Subject.__index = Subject
classes.Subject = Subject
function Subject.new()
  local s = setmetatable({ observers = {} }, Subject)
  s._subscribe = function(o)
    s.observers[#s.observers + 1] = o
    return Disposable.new(function()
      for i, x in ipairs(s.observers) do if x == o then table.remove(s.observers, i) break end end
    end)
  end
  return s
end
function Subject:OnNext(v)
  local list = { table.unpack(self.observers) }
  for _, o in ipairs(list) do o.next(v) end
end
function Subject:OnCompleted()
  for _, o in ipairs({ table.unpack(self.observers) }) do o.completed() end
end

-- BehaviorSubject: replays the latest value to new subscribers
local BS = setmetatable({ __name = "BehaviorSubject" }, { __index = Subject })
BS.__index = BS
classes.BehaviorSubject = BS
function BS.new(v)
  local s = Subject.new()
  setmetatable(s, BS)
  s.value = v
  local base = s._subscribe
  s._subscribe = function(o) o.next(s.value); return base(o) end
  return s
end
function BS:OnNext(v) self.value = v; Subject.OnNext(self, v) end

-- AsyncSubject: delivers the last value once completed
local AS = setmetatable({ __name = "AsyncSubject" }, { __index = Subject })
AS.__index = AS
classes.AsyncSubject = AS
function AS.new()
  local s = Subject.new()
  setmetatable(s, AS)
  local base = s._subscribe
  s._subscribe = function(o)
    if s.done then o.next(s.last); o.completed(); return Disposable.new() end
    return base(o)
  end
  return s
end
function AS:OnNext(v) self.last = v end
function AS:OnCompleted() self.done = true; for _, o in ipairs({ table.unpack(self.observers) }) do o.next(self.last); o.completed() end end

classes.Unit = { Default = {} }
classes.Tuple = { new = function(a, b, c) return { Item1 = a, Item2 = b, Item3 = c } end }
classes.Tuple.Create = classes.Tuple.new
classes.String = setmetatable({ Empty = "" }, { __index = function(_, k) return STR[k] end })
classes.KeyValuePair = { new = function(k, v) return { Key = k, Value = v } end }
classes.Delegate = { Combine = function(a, b)
  if a == nil or a == NULL then return b end
  if b == nil or b == NULL then return a end
  return function(...) a(...); return b(...) end
end }

-- ReactiveProperty: emits the current value on subscribe and on every change
local RP = setmetatable({ __name = "ReactiveProperty" }, { __index = Observable })
classes.ReactiveProperty = RP
RP.__index = function(t, k)
  if k == "Value" then return rawget(t, "_v") end
  return RP[k]
end
RP.__newindex = function(t, k, v)
  if k == "Value" then
    if rawget(t, "_v") ~= v then
      rawset(t, "_v", v)
      t.subject:OnNext(v)
    end
    return
  end
  rawset(t, k, v)
end
function RP.new(v)
  local p = setmetatable({ _v = v, subject = Subject.new() }, RP)
  rawset(p, "_subscribe", function(o)
    o.next(rawget(p, "_v"))
    return p.subject._subscribe(o)
  end)
  return p
end
function RP:SetValueAndForceNotify(v) rawset(self, "_v", v); self.subject:OnNext(v) end
classes.BoolReactiveProperty = RP
classes.IntReactiveProperty = RP
classes.StringReactiveProperty = RP

-- ReactiveCollection
local RC = { __name = "ReactiveCollection" }
classes.ReactiveCollection = RC
RC.__index = function(t, k)
  if k == "Count" then return t.list.n end
  return RC[k] or List[k] and function(self, ...) return List[k](self.list, ...) end
end
function RC.new() return setmetatable({ list = List.new(), added = Subject.new(), removed = Subject.new(), reset = Subject.new() }, RC) end
function RC:Add(v)
  self.list:Add(v)
  self.added:OnNext({ Value = v, Index = self.list.n - 1 })
end
function RC:Clear() self.list:Clear(); self.reset:OnNext(nil) end
function RC:RemoveAt(i) local v = self.list:__idx(i); self.list:RemoveAt(i); self.removed:OnNext({ Value = v, Index = i }) end
function RC:Remove(v) local i = self.list:IndexOf(v); if i >= 0 then self:RemoveAt(i) return true end return false end
function RC:ObserveAdd() return self.added end
function RC:ObserveRemove() return self.removed end
function RC:ObserveReset() return self.reset end
function RC:ObserveCountChanged()
  local s = self
  return obs(function(o)
    local d1 = s.added._subscribe({ next = function() o.next(s.list.n) end, completed = function() end })
    local d2 = s.removed._subscribe({ next = function() o.next(s.list.n) end, completed = function() end })
    return Disposable.new(function() d1:Dispose(); d2:Dispose() end)
  end)
end
function RC:__idx(i) return self.list:__idx(i) end
function RC:__each() return self.list:__each() end
function RC:ToList() return self.list:ToList() end

-- obj:ObserveEveryValueChanged(fn): polls every frame, emits the first value and every change
local function every_value_changed(target, fn)
  return obs(function(o)
    local has, last = false, nil
    local h
    h = core.poll(function()
      local ok, v = pcall(fn, target)
      if not ok then return end
      if not has or v ~= last then has, last = true, v; o.next(v) end
    end)
    return h
  end)
end
core.every_value_changed = every_value_changed

function Observable.Interval(span)
  return obs(function(o)
    local n, nextT = 0, core.now() + span.ms / 1000
    return core.poll(function()
      if core.now() >= nextT then nextT = nextT + span.ms / 1000; o.next(n); n = n + 1 end
    end)
  end)
end
function Observable.Timer(span)
  return obs(function(o)
    local t = core.now() + span.ms / 1000
    local h
    h = core.poll(function() if core.now() >= t then h:Dispose(); o.next(0); o.completed() end end)
    return h
  end)
end
function Observable.EveryUpdate()
  return obs(function(o)
    local n = 0
    return core.poll(function() o.next(n); n = n + 1 end)
  end)
end
function Observable.Return(v) return obs(function(o) o.next(v); o.completed(); return Disposable.new() end) end

-- TimeSpan
TimeSpan = {
  FromMilliseconds = function(ms) return { ms = ms } end,
  FromSeconds = function(s) return { ms = s * 1000 } end,
  FromMinutes = function(m) return { ms = m * 60000 } end,
}
classes.TimeSpan = TimeSpan

-- ------------------------------------------------------------------ UniTask (awaits are direct calls)
UniTask = { __name = "UniTask" }
classes.UniTask = UniTask
function UniTask.Delay(ms, a, b, token)
  -- overloads: Delay(ms), Delay(ms, ignoreTimeScale, timing, token), Delay(TimeSpan, ...)
  if type(ms) == "table" then ms = ms.ms end
  local tok = token
  if type(a) == "table" and a ~= NULL and a.IsCancellationRequested ~= nil then tok = a end
  core.wait_ms(ms, tok)
end
function UniTask.DelayFrame(n) core.wait_frames(n) end
function UniTask.Yield() core.wait_frames(1) end
function UniTask.NextFrame() core.wait_frames(1) end
function UniTask.WaitUntil(fn, timing, token)
  core.wait_until(function()
    if token and token ~= NULL and token.IsCancellationRequested then return true end
    return fn()
  end)
end
function UniTask.WaitWhile(fn) core.wait_until(function() return not fn() end) end
-- arguments were already awaited sequentially by the caller; nothing left to wait for
function UniTask.WhenAny() return 0 end
function UniTask.WhenAll() end
UniTask.CompletedTask = nil

-- CancellationTokenSource / token
local CTS = { __name = "CancellationTokenSource" }
CTS.__index = function(t, k)
  if k == "Token" then return t end
  if k == "IsCancellationRequested" then return rawget(t, "_c") or false end
  return CTS[k]
end
classes.CancellationTokenSource = CTS
function CTS.new() return setmetatable({ _c = false }, CTS) end
function CTS:Cancel() rawset(self, "_c", true) end
function CTS:Dispose() end
function CTS:ThrowIfCancellationRequested()
  if rawget(self, "_c") then
    if core.debug_cancel then LOG("[cancel]", debug.traceback("", 2)) end
    error({ canceled = true }, 0)
  end
end
classes.CancellationToken = { new = function() return CTS.new() end }

-- awaiting helpers used by overrides
core.Subject = Subject
core.RP = RP
core.RC = RC
core.Disposable = Disposable
return Observable
