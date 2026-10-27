-- Full-screen special windows of the horror / ending sequences, split across both screens.
-- Hakkyo: windows flee from the stylus. Medama: eyes follow the stylus. BrowserCrasher / Ideon:
-- window storms on both screens, tap to close (bottom).
local core = require("runtime.core")
local G = require("runtime.gfx")
local I = require("runtime.input")
local T = require("ui.theme")
local c = T.c

local M = {}
local storms = setmetatable({}, { __mode = "k" })

local function storm(w)
  local s = storms[w]
  if not s then
    s = {}
    for i = 1, 14 do
      s[i] = { x = math.random(0, 280), y = math.random(0, 200), top = i % 2 == 0, vx = 0, vy = 0, alive = true }
    end
    storms[w] = s
  end
  return s
end

function M.draw_top(w)
  local k = w.kind
  if k == "hakkyo" or k == "darkness" then
    for _ = 1, 6 do
      G.rect(math.random(0, 380), math.random(0, 230), math.random(10, 80), math.random(2, 10), (math.random(0, 0xffffff) << 8) | 0x90)
    end
    G.rect(0, 0, 400, 240, k == "darkness" and 0x40000060 or 0x30000040)
  elseif k == "die" then
    G.rect(0, 0, 400, 240, 0x000000ff)
    for i = 0, 40 do G.text("死ね", math.random(0, 380), math.random(0, 228), 0xff2040ff) end
  elseif k == "medama" then
    G.draw("eye_0", 200, 120, { ax = 0.5, ay = 0.5, fit = { 400, 240 } })
  elseif k == "crash" or k == "ideon" then
    for _, win in ipairs(storm(w)) do
      if win.alive and win.top then
        T.window(win.x + 40, win.y, 120, 70, w.app)
      end
    end
  end
end

function M.draw_bottom(w)
  local k = w.kind
  if k == "hakkyo" then
    -- desktop windows that run away from the stylus
    for _, win in ipairs(storm(w)) do
      if not win.top then
        if I.touching then
          local dx, dy = win.x + 50 - I.tx, win.y + 30 - I.ty
          local d = math.max(1, math.sqrt(dx * dx + dy * dy))
          if d < 90 then win.x = win.x + dx / d * 6; win.y = win.y + dy / d * 6 end
        end
        win.x = math.max(-60, math.min(280, win.x))
        win.y = math.max(-30, math.min(200, win.y))
        T.window(win.x, win.y, 100, 60, "...")
      end
    end
  elseif k == "medama" then
    G.rect(0, 0, 320, 240, 0x000000ff)
    local tx, ty = I.touching and I.tx or 160, I.touching and I.ty or 120
    for i = 0, 2 do
      local ex, ey = 60 + i * 100, 120
      G.rect(ex - 30, ey - 18, 60, 36, c.white)
      local ang = math.atan(ty - ey, tx - ex)
      G.rect(ex + math.cos(ang) * 14 - 8, ey + math.sin(ang) * 8 - 8, 16, 16, 0x000000ff)
    end
  elseif k == "crash" or k == "ideon" then
    local left = 0
    for i, win in ipairs(storm(w)) do
      if win.alive and not win.top then
        left = left + 1
        T.window(win.x, win.y, 120, 70, w.app)
        local id = "storm" .. i
        if I.focusable(id, win.x, win.y, 120, 70) then T.focus_ring(win.x, win.y, 120, 70) end
        if I.tapped(win.x, win.y, 120, 70) or I.activated(id) then win.alive = false; AudioManager:PlaySeByType("SE_click") end
      end
    end
  elseif k == "die" then
    G.rect(0, 0, 320, 240, 0x000000e0)
  end
end

return M
