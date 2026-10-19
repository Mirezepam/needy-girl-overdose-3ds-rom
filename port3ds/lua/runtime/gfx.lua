-- Sprites from the atlas pages built by build_assets.py, with an LRU texture cache sized for
-- Old 3DS, frame animations by sprite-name sequence, and text helpers.
local core = require("runtime.core")

local G = {}
local index = dofile(sys.data .. "gfx/index.lua")
local sprites, groups = index.sprites, index.groups
local pages = {}       -- "group_page" -> {id, w, h, bytes, last}
local BUDGET = 20 * 1024 * 1024
local frame = 0
G.screen = 0           -- 0 top, 1 bottom
G.W, G.H = 400, 240

function G.set_budget(bytes) BUDGET = bytes end

local function evict(need)
  local _, used = sys.mem()
  while used + need > BUDGET do
    local oldest, key
    for k, p in pairs(pages) do
      if p.last < frame and (not oldest or p.last < oldest.last) then oldest, key = p, k end
    end
    if not oldest then return end
    sys.tex_free(oldest.id)
    pages[key] = nil
    _, used = sys.mem()
  end
end

local function page(group, p)
  local key = group .. "_" .. p
  local pg = pages[key]
  if pg then pg.last = frame; return pg end
  local size = groups[group] and groups[group].sizes[p + 1]
  if size then evict(size[1] * size[2] * 2) end
  local id, w, h = sys.tex_load(sys.data .. "gfx/" .. key .. ".ntx")
  if not id then
    LOG_ONCE("tex:" .. key, "texture missing", key)
    return nil
  end
  pg = { id = id, w = w, h = h, last = frame }
  pages[key] = pg
  return pg
end

function G.begin_frame() frame = frame + 1 end

function G.exists(name) return sprites[name] ~= nil end

-- full (untrimmed) size of a sprite
function G.size(name)
  local s = sprites[name]
  if not s then return 0, 0 end
  return s[9], s[10]
end

-- draw(name, x, y, opts): opts.scale, .sx/.sy, .flip, .alpha, .tint, .blend, .angle, .ax/.ay (anchor 0..1), .w/.h (fit)
function G.draw(name, x, y, o)
  local s = sprites[name]
  if not s then return false end
  local pg = page(s[1], s[2])
  if not pg then return false end
  o = o or {}
  local sx = o.sx or o.scale or 1
  local sy = o.sy or o.scale or 1
  if o.w then sx = o.w / s[9]; sy = o.h and o.h / s[10] or sx end
  if o.fit then local f = math.min(o.fit[1] / s[9], o.fit[2] / s[10]); sx, sy = f, f end
  if o.flip then sx = -sx end   -- mirrored: drawn to the left of x
  x = x - (o.ax or 0) * s[9] * sx
  y = y - (o.ay or 0) * s[10] * sy
  sys.draw(pg.id, s[3], s[4], s[5], s[6], x + s[7] * sx, y + s[8] * sy, sx, sy,
    o.alpha or 1, o.tint or 0xffffffff, o.blend or 0, o.angle or 0)
  return true
end

-- ------------------------------------------------------------------ animations
local anim_cache = {}
function G.frames(prefix)
  local f = anim_cache[prefix]
  if f then return f end
  f = {}
  for i = 0, 400 do
    local n
    for _, fmt in ipairs({ "%s_%03d", "%s%03d", "%s_%02d", "%s%02d" }) do
      local c = string.format(fmt, prefix, i)
      if sprites[c] then n = c; break end
    end
    if not n then
      if i > 1 then break end
    else
      f[#f + 1] = n
    end
  end
  if #f == 0 and sprites[prefix] then f[1] = prefix end
  anim_cache[prefix] = f
  return f
end

-- draws animation `prefix` at time t (seconds); returns false if it does not exist
function G.anim(prefix, t, x, y, o, fps, loop)
  local f = G.frames(prefix)
  if #f == 0 then return false end
  local i = math.floor(t * (fps or 12))
  if loop == false then i = math.min(i, #f - 1) else i = i % #f end
  return G.draw(f[i + 1], x, y, o)
end

function G.anim_length(prefix, fps) return #G.frames(prefix) / (fps or 12) end

-- ------------------------------------------------------------------ original clips (real timing)
-- data/anims.lua is exported from the game's AnimationClips: per clip its length, loop flag and
-- sprite keys {time, sprite}. Non-looping clips hold their last frame, like Unity.
local anims_ok, ANIMS = pcall(dofile, sys.data .. "data/anims.lua")
if not anims_ok then ANIMS = { clips = {}, controllers = {} } end
G.ANIMS = ANIMS

function G.clip_info(name) return ANIMS.clips[name] end

-- sprite shown by clip `name` at time t; returns sprite, finished
local lower_clips
local function find_clip(name)
  local c = ANIMS.clips[name]
  if c or type(name) ~= "string" then return c end
  if not lower_clips then
    lower_clips = {}
    for k, v in pairs(ANIMS.clips) do lower_clips[k:lower()] = v end
  end
  c = lower_clips[name:lower()]
  ANIMS.clips[name] = c or false
  return c
end
G.find_clip = find_clip

function G.clip_frame(name, t)
  local c = find_clip(name)
  if not c then return nil end
  local keys = c.keys
  if #keys == 0 then return nil end
  local len = c.len > 0 and c.len or keys[#keys][1]
  local finished = false
  if c.loop and len > 0 then t = t % len
  elseif t >= len then t = len; finished = true end
  -- binary search the last key with time <= t
  local lo, hi = 1, #keys
  while lo < hi do
    local mid = (lo + hi + 1) // 2
    if keys[mid][1] <= t then lo = mid else hi = mid - 1 end
  end
  return keys[lo][2], finished
end

-- draws clip `name` (original timing) or falls back to a 12 fps frame sequence
function G.play(name, t, x, y, o)
  local spr = G.clip_frame(name, t)
  if spr and G.draw(spr, x, y, o) then return true end
  return G.anim(name, t, x, y, o, 12, true)
end

-- ------------------------------------------------------------------ 9-slice (original UI pieces)
-- draws sprite `name` stretched to w x h keeping its borders; scale applies to the borders
-- (0.5 renders the game's 2x pixel art at native size)
function G.draw9(name, x, y, w, h, scale, o)
  local s = sprites[name]
  if not s then return false end
  local bl, bb, br, bt = s[11], s[12], s[13], s[14]
  if not bl then return G.draw(name, x, y, { w = w, h = h, alpha = o and o.alpha, tint = o and o.tint, blend = o and o.blend }) end
  local pg = page(s[1], s[2])
  if not pg then return false end
  scale = scale or 0.5
  local sx, sy, sw, sh = s[3], s[4], s[5], s[6]
  local alpha, tint, blend = o and o.alpha or 1, o and o.tint or 0xffffffff, o and o.blend or 0
  -- source columns/rows (Unity border: left, bottom, right, top)
  local cx = { sx, sx + bl, sx + sw - br }
  local cw = { bl, sw - bl - br, br }
  local ry = { sy, sy + bt, sy + sh - bb }
  local rh = { bt, sh - bt - bb, bb }
  local dl, dr, dt, db = bl * scale, br * scale, bt * scale, bb * scale
  if dl + dr > w then local k = w / (dl + dr); dl, dr = dl * k, dr * k end
  if dt + db > h then local k = h / (dt + db); dt, db = dt * k, db * k end
  local dx = { x, x + dl, x + w - dr }
  local dw = { dl, w - dl - dr, dr }
  local dy = { y, y + dt, y + h - db }
  local dh = { dt, h - dt - db, db }
  for r = 1, 3 do
    for c = 1, 3 do
      if cw[c] > 0 and rh[r] > 0 and dw[c] > 0 and dh[r] > 0 then
        sys.draw(pg.id, cx[c], ry[r], cw[c], rh[r], dx[c], dy[r], dw[c] / cw[c], dh[r] / rh[r], alpha, tint, blend, 0)
      end
    end
  end
  return true
end

-- ------------------------------------------------------------------ primitives & text
function G.rect(x, y, w, h, c) sys.rect(x, y, w, h, c) end
function G.frame_rect(x, y, w, h, c, t)
  t = t or 1
  sys.rect(x, y, w, t, c); sys.rect(x, y + h - t, w, t, c)
  sys.rect(x, y, t, h, c); sys.rect(x + w - t, y, t, h, c)
end
function G.text(s, x, y, c, scale, wrap, maxLines)
  if s == nil or s == NULL then return 0, 0 end
  return sys.text(tostring(s), x, y, c or 0xffffffff, scale or 1, wrap or 0, maxLines or 0)
end
function G.text_center(s, cx, y, c, scale, wrap)
  local w = G.measure(s, scale, wrap)
  return G.text(s, cx - w / 2, y, c, scale, wrap)
end
-- text layout is the most expensive per-frame call: memoize measurements (UI strings repeat every frame)
local mcache, mcount = {}, 0
function G.measure(s, scale, wrap, maxLines)
  s = tostring(s)
  local key = s .. "\0" .. (scale or 1) .. "\0" .. (wrap or 0) .. "\0" .. (maxLines or 0)
  local m = mcache[key]
  if m then return m[1], m[2] end
  local w, h = sys.measure(s, scale or 1, wrap or 0, maxLines or 0)
  mcount = mcount + 1
  if mcount > 600 then mcache, mcount = {}, 0 end
  mcache[key] = { w, h }
  return w, h
end
function G.clip(x, y, w, h) sys.scissor(x, y, w, h) end
function G.unclip() sys.scissor() end
G.LH = sys.line_height()

function G.stats()
  local n = 0
  for _ in pairs(pages) do n = n + 1 end
  local lin, tex, lua = sys.mem()
  return n, tex, lin, lua
end

return G
