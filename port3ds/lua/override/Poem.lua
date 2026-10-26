-- Poem (PoemCanvas): fades a dark cover in (0.4 s), types the poem at 0.12 s per character with
-- SE_per on each one, raises the noise, waits 1.8 s and returns (StartPoem is awaited by its
-- callers); CleanPoem fades it out in 1.4 s. ui/top.lua and ui/bottom.lua draw it from C.state.
local core = require("runtime.core")
local C = class("Poem", "SingletonMonoBehaviour")

C.state = nil

function C:__fields() self.playingAnimation = false end
function C:Awake() end
function C:Start() end

local function length(s) local ok, n = pcall(utf8.len, s); return ok and n or #s end

function C:StartPoem(poem, isDaypassing)
  if not coroutine.isyieldable() then spawn(C.StartPoem, self, poem, isDaypassing) return end
  if self.playingAnimation or type(poem) ~= "string" then return end
  self.playingAnimation = true
  local st = { text = poem, t0 = core.now(), len = length(poem), fade = nil }
  C.state = st
  local per = core.fast and 0.02 or 0.12
  local shown = 0
  core.wait_ms(400)
  local typing_end = core.now() + st.len * per
  st.type0 = core.now()
  while core.now() < typing_end do
    local n = math.floor((core.now() - st.type0) / per)
    if n > shown then
      shown = n
      local cut = utf8.offset(poem, n) or 1
      local ch = poem:sub(cut, (utf8.offset(poem, n + 1) or (#poem + 1)) - 1)
      if ch ~= "\n" and ch ~= " " and ch ~= "　" then AudioManager:PlaySeByType("SE_per") end
    end
    core.wait_ms(16)
  end
  st.done = true
  core.wait_ms(core.fast and 300 or 2000)
  self.playingAnimation = false
end

function C:SkipPoem()
  if C.state then C.state.done = true end
end

function C:CleanPoem()
  local st = C.state
  if not st then return end
  st.fade = core.now()
  spawn(function()
    core.wait_ms(1400)
    if C.state == st then C.state = nil end
  end)
end

-- draw helper: alpha of the cover and the typed text
function C.visible_text()
  local st = C.state
  if not st then return nil end
  local a = math.min(1, (core.now() - st.t0) / 0.4)
  if st.fade then a = math.max(0, 1 - (core.now() - st.fade) / 1.4) end
  local text = ""
  if st.done then text = st.text
  elseif st.type0 then
    local per = core.fast and 0.02 or 0.12
    local n = math.floor((core.now() - st.type0) / per)
    local cut = utf8.offset(st.text, n + 1)
    text = cut and st.text:sub(1, cut - 1) or st.text
  end
  return text, a
end

return C
