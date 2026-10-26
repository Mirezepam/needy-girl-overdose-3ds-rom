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

-- frees least recently used pages until `need` bytes fit in the budget and in the linear heap
-- (audio buffers and cached effects share that heap, so the budget alone is not enough)
local RESERVE = 1536 * 1024
local function evict(need, all)
  local free, used = sys.mem()
  while all or used + need > BUDGET or free < need + RESERVE do
    local oldest, key
    for k, p in pairs(pages) do
      if p.last < frame and (not oldest or p.last < oldest.last) then oldest, key = p, k end
    end
    if not oldest then return end
    sys.tex_free(oldest.id)
    pages[key] = nil
    free, used = sys.mem()
  end
end

local function page(group, p)
  local key = group .. "_" .. p
  local pg = pages[key]
  if pg then pg.last = frame; return pg end
  local size = groups[group] and groups[group].sizes[p + 1]
  local need = size and size[1] * size[2] * 2 or 0
  evict(need)
  local id, w, h = sys.tex_load(sys.data .. "gfx/" .. key .. ".ntx")
  if not id then
    -- the heap may be fragmented: drop every page not drawn this frame and try once more
    evict(need, true)
    id, w, h = sys.tex_load(sys.data .. "gfx/" .. key .. ".ntx")
  end
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
  -- whole pixels only: odd borders at scale 0.5 put the seams on half pixels and the slices then
  -- left 1 px gaps (what was behind showed through as lines)
  local fl = math.floor
  x, y, w, h = fl(x + 0.5), fl(y + 0.5), fl(w + 0.5), fl(h + 0.5)
  local dl, dr, dt, db = fl(bl * scale + 0.5), fl(br * scale + 0.5), fl(bt * scale + 0.5), fl(bb * scale + 0.5)
  if dl + dr > w then local k = w / (dl + dr); dl = fl(dl * k); dr = w - dl end
  if dt + db > h then local k = h / (dt + db); dt = fl(dt * k); db = h - dt end
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
-- the game's texts carry TextMeshPro rich-text tags (<br>, <mspace=..>, <color=..>, <size=..>):
-- <br> becomes a line break, the other tags are dropped
local cleaned = {}
local function clean(s)
  s = tostring(s)
  if not s:find("<", 1, true) then return s end
  local r = cleaned[s]
  if r then return r end
  r = s:gsub("<[bB][rR]%s*/?>", "\n"):gsub("</?%a[%w%-]*=?[^<>]*>", "")
  cleaned[s] = r
  return r
end
G.clean = clean

-- Emoji: the bitmap font has none, the game drew them from TextMeshPro sprite assets. Texts that
-- contain one are laid out here (words + emoji sprites, same wrapping rules) and the layout is
-- cached; everything else goes straight to the C text renderer.
local EMOJI = require("runtime.emoji_map")
local SKIP = { [0xFE0F] = true, [0x200D] = true, [0xFE0E] = true }
local emoji_flag, layouts, nlayouts = {}, {}, 0

local function has_emoji(s)
  local f = emoji_flag[s]
  if f ~= nil then return f end
  f = false
  if s:find("[\226-\244]") then
    -- walk the whole string: invalid UTF-8 makes it a plain text (utf8.codes would raise later)
    local ok = pcall(function()
      for _, cp in utf8.codes(s) do if EMOJI[cp] then f = true end end
    end)
    if not ok then f = false end
  end
  emoji_flag[s] = f
  return f
end

local function rich_layout(s, scale, wrap, maxLines)
  local key = s .. "\0" .. scale .. "\0" .. wrap .. "\0" .. maxLines
  local L = layouts[key]
  if L then return L end
  local lh = G.LH * scale
  local space = sys.measure("a a", scale, 0, 0) - sys.measure("aa", scale, 0, 0)
  -- tokens: {"w", text} words, {"s"} spaces, {"n"} line breaks, {"e", sprite} emoji
  local toks, word = {}, {}
  local function flush() if #word > 0 then toks[#toks + 1] = { "w", table.concat(word) }; word = {} end end
  for _, cp in utf8.codes(s) do
    if EMOJI[cp] then flush(); toks[#toks + 1] = { "e", EMOJI[cp] }
    elseif cp == 10 then flush(); toks[#toks + 1] = { "n" }
    elseif cp == 32 then flush(); toks[#toks + 1] = { "s" }
    elseif not SKIP[cp] then
      word[#word + 1] = utf8.char(cp)
      if cp >= 0x3000 then flush() end   -- CJK: any character may start a new line
    end
  end
  flush()
  local ops, line, cx, maxw = {}, 0, 0, 0
  local cur = nil      -- text op being extended on the current line
  local done = false
  local function newline()
    maxw = math.max(maxw, cx)
    line, cx, cur = line + 1, 0, nil
    if maxLines > 0 and line >= maxLines then done = true end
  end
  for _, t in ipairs(toks) do
    if done then break end
    if t[1] == "n" then newline()
    else
      local tw = t[1] == "s" and space or (t[1] == "e" and lh or sys.measure(t[2], scale, 0, 0))
      if wrap > 0 and cx > 0 and cx + tw > wrap and t[1] ~= "s" then newline() end
      if not done and not (t[1] == "s" and cx == 0 and line > 0) then
        if t[1] == "e" then
          ops[#ops + 1] = { "e", t[2], cx, line * lh }
          cur = nil
        else
          local str = t[1] == "s" and " " or t[2]
          if cur then cur[2] = cur[2] .. str else cur = { "t", str, cx, line * lh }; ops[#ops + 1] = cur end
        end
        cx = cx + tw
      end
    end
  end
  maxw = math.max(maxw, cx)
  L = { ops = ops, w = maxw, h = (math.min(line + 1, maxLines > 0 and maxLines or line + 1)) * lh }
  nlayouts = nlayouts + 1
  if nlayouts > 300 then layouts, nlayouts, emoji_flag = {}, 0, {} end
  layouts[key] = L
  return L
end

function G.text(s, x, y, c, scale, wrap, maxLines)
  if s == nil or s == NULL then return 0, 0 end
  s = clean(s)
  if has_emoji(s) then
    local L = rich_layout(s, scale or 1, wrap or 0, maxLines or 0)
    local lh = G.LH * (scale or 1)
    for _, op in ipairs(L.ops) do
      if op[1] == "t" then sys.text(op[2], x + op[3], y + op[4], c or 0xffffffff, scale or 1, 0, 0)
      else G.draw(op[2], x + op[3], y + op[4] - 1, { fit = { lh, lh } }) end
    end
    return L.h, L.w
  end
  if (maxLines or 0) > 0 and (wrap or 0) > 0 then s = G.ellipsize(s, scale or 1, wrap, maxLines) end
  return sys.text(s, x, y, c or 0xffffffff, scale or 1, wrap or 0, maxLines or 0)
end

-- a text that needs more than maxLines lines ends in "…" on the last one instead of being cut
local ell_cache, ell_n = {}, 0
function G.ellipsize(s, scale, wrap, maxLines)
  local key = s .. "\0" .. scale .. "\0" .. wrap .. "\0" .. maxLines
  local r = ell_cache[key]
  if r then return r end
  local lh = G.LH * scale
  local function lines(t) local _, h = sys.measure(t, scale, wrap, 0); return math.floor(h / lh + 0.5) end
  r = s
  if lines(s) > maxLines then
    local ok, n = pcall(utf8.len, s)
    if ok and n then
      local lo, hi = 0, n
      while lo < hi do   -- longest prefix that still fits with the ellipsis
        local mid = (lo + hi + 1) // 2
        local cut = s:sub(1, (utf8.offset(s, mid + 1) or (#s + 1)) - 1)
        if lines(cut .. "…") <= maxLines then lo = mid else hi = mid - 1 end
      end
      r = s:sub(1, (utf8.offset(s, lo + 1) or (#s + 1)) - 1):gsub("%s+$", "") .. "…"
    end
  end
  ell_n = ell_n + 1
  if ell_n > 400 then ell_cache, ell_n = {}, 0 end
  ell_cache[key] = r
  return r
end
function G.text_center(s, cx, y, c, scale, wrap)
  local w = G.measure(s, scale, wrap)
  return G.text(s, cx - w / 2, y, c, scale, wrap)
end
-- text layout is the most expensive per-frame call: memoize measurements (UI strings repeat every frame)
local mcache, mcount = {}, 0
function G.measure(s, scale, wrap, maxLines)
  s = clean(s)
  local key = s .. "\0" .. (scale or 1) .. "\0" .. (wrap or 0) .. "\0" .. (maxLines or 0)
  local m = mcache[key]
  if m then return m[1], m[2] end
  local w, h
  if has_emoji(s) then
    local L = rich_layout(s, scale or 1, wrap or 0, maxLines or 0)
    w, h = L.w, L.h
  else
    w, h = sys.measure(s, scale or 1, wrap or 0, maxLines or 0)
  end
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
