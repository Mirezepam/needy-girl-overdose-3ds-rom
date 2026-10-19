-- The stylus has no cursor. Scripted cursor moves (horror scenes, endings) draw a fake cursor
-- on the bottom screen.
local core = require("runtime.core")
local C = class("CursorManager", "SingletonMonoBehaviour")

function C:__fields()
  self.fake = { x = 160, y = 120, visible = false, sprite = nil }
  local fake = self.fake
  self.CursorPosition = setmetatable({}, { __index = function(_, k) return fake[k] end, __newindex = function(_, k, v) fake[k] = v end })
end
function C:SetCursor(tex) self.fake.sprite = tex end
function C:SetCursorShowHide(show) self.fake.visible = show and true or false end
function C:MoveToAsync(target, seconds)
  local f = self.fake
  f.visible = true
  local sx, sy = f.x, f.y
  local tx, ty = target and target.x or 160, target and target.y or 120
  -- original coordinates are 1920x1080 desktop space: map to the bottom screen
  if tx > 320 or ty > 240 then tx, ty = tx / 6, ty / 4.5 end
  local t0, dur = core.now(), (seconds or 1)
  core.wait_until(function()
    local k = math.min(1, (core.now() - t0) / dur)
    f.x, f.y = sx + (tx - sx) * k, sy + (ty - sy) * k
    return k >= 1
  end)
end
function C:MoveCursorToCenter() self.fake.x, self.fake.y = 160, 120 end
function C:DisableLiveCursorMode() end
function C:EnableLiveCursorMode() end
return C
