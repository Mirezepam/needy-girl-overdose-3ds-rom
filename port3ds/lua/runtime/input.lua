-- Buttons + stylus gestures (tap, long press, drag/scroll, swipe) and D-pad focus navigation
-- for the immediate-mode UI. Every touch action also has a button equivalent.
local core = require("runtime.core")

local I = {}
core.input = I

I.KEY = {
  A = 1 << 0, B = 1 << 1, SELECT = 1 << 2, START = 1 << 3, DRIGHT = 1 << 4, DLEFT = 1 << 5,
  DUP = 1 << 6, DDOWN = 1 << 7, R = 1 << 8, L = 1 << 9, X = 1 << 10, Y = 1 << 11,
  ZL = 1 << 14, ZR = 1 << 15, TOUCH = 1 << 20, CRIGHT = 1 << 28, CLEFT = 1 << 29, CUP = 1 << 30, CDOWN = 1 << 31,
}
local K = I.KEY
I.down, I.held, I.up = 0, 0, 0
I.tx, I.ty = 0, 0
I.touching = false
local t0x, t0y, t0time, moved = 0, 0, 0, false
local longFired = false

function I.update(dt, down, held, up, tx, ty)
  I.down, I.held, I.up = down, held, up
  I.tap, I.long, I.swipe, I.tap_down, I.tap_up = nil, nil, nil, false, false
  I.drag_dy, I.drag_dx = 0, 0
  local now = core.now()
  if down & K.TOUCH ~= 0 then
    I.touching = true
    t0x, t0y, t0time, moved, longFired = tx, ty, now, false, false
    I.tx, I.ty = tx, ty
    I.tap_down = true
  elseif held & K.TOUCH ~= 0 then
    I.drag_dx, I.drag_dy = tx - I.tx, ty - I.ty
    I.tx, I.ty = tx, ty
    if math.abs(tx - t0x) > 6 or math.abs(ty - t0y) > 6 then moved = true end
    if not moved and not longFired and now - t0time > 0.5 then
      longFired = true
      I.long = { x = t0x, y = t0y }
    end
  elseif up & K.TOUCH ~= 0 then
    I.touching = false
    I.tap_up = true
    local dx, dy, dur = I.tx - t0x, I.ty - t0y, now - t0time
    if not moved and not longFired then
      I.tap = { x = t0x, y = t0y }
    elseif dur < 0.45 and math.abs(dx) > 40 and math.abs(dx) > math.abs(dy) * 1.5 then
      I.swipe = { dir = dx < 0 and "left" or "right", x = t0x, y = t0y }
    end
  end
  I.focus_update()
end

function I.pressed(k) return I.down & k ~= 0 end
function I.isheld(k) return I.held & k ~= 0 end

local function inside(p, x, y, w, h) return p and p.x >= x and p.x < x + w and p.y >= y and p.y < y + h end
I.inside = inside

-- consumes the tap if it hit the rect
function I.tapped(x, y, w, h)
  if inside(I.tap, x, y, w, h) then I.tap = nil; return true end
  return false
end
function I.long_pressed(x, y, w, h)
  if inside(I.long, x, y, w, h) then I.long = nil; return true end
  return false
end
function I.swiped(x, y, w, h)
  if I.swipe and inside(I.swipe, x, y, w, h) then local s = I.swipe.dir; I.swipe = nil; return s end
end
function I.touching_in(x, y, w, h) return I.touching and inside({ x = I.tx, y = I.ty }, x, y, w, h) end

-- ------------------------------------------------------------------ D-pad focus
-- Widgets register their rects every frame; the previous frame's list drives navigation.
local focusables, prev = {}, {}
I.focus_id = nil
I.focus_visible = false

function I.focusable(id, x, y, w, h)
  focusables[#focusables + 1] = { id = id, x = x, y = y, w = w, h = h }
  return I.focus_visible and I.focus_id == id
end

-- an overlay (modal dialog, start menu) drops what was registered below it
function I.focus_reset() focusables = {} end

function I.activated(id)
  return I.focus_visible and I.focus_id == id and I.pressed(K.A)
end

local function center(f) return f.x + f.w / 2, f.y + f.h / 2 end

function I.focus_update()
  prev, focusables = focusables, {}
  I.last_focusables = prev   -- (test bots tap these)
  if I.tap_down then I.focus_visible = false end
  local dir
  if I.pressed(K.DUP) or I.pressed(K.CUP) then dir = "up"
  elseif I.pressed(K.DDOWN) or I.pressed(K.CDOWN) then dir = "down"
  elseif I.pressed(K.DLEFT) or I.pressed(K.CLEFT) then dir = "left"
  elseif I.pressed(K.DRIGHT) or I.pressed(K.CRIGHT) then dir = "right" end
  if #prev == 0 then return end
  local cur
  for _, f in ipairs(prev) do if f.id == I.focus_id then cur = f end end
  if not dir then
    if not cur and I.focus_visible then I.focus_id = prev[1].id end
    return
  end
  if not I.focus_visible or not cur then
    I.focus_visible = true
    I.focus_id = (cur or prev[1]).id
    return
  end
  local cx, cy = center(cur)
  local best, bestScore
  for _, f in ipairs(prev) do
    if f ~= cur then
      local fx, fy = center(f)
      local dx, dy = fx - cx, fy - cy
      local ok = (dir == "up" and dy < -2) or (dir == "down" and dy > 2) or (dir == "left" and dx < -2) or (dir == "right" and dx > 2)
      if ok then
        local main = (dir == "up" or dir == "down") and math.abs(dy) or math.abs(dx)
        local cross = (dir == "up" or dir == "down") and math.abs(dx) or math.abs(dy)
        local score = main + cross * 2
        if not bestScore or score < bestScore then best, bestScore = f, score end
      end
    end
  end
  if best then I.focus_id = best.id end
end

return I
