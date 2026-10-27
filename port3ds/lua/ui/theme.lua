-- Windose look built from the game's own UI sprites and palette (taken from the original prefabs:
-- WindowBase2D, BaseButton, InputFieldBackground...). UI art is drawn at scale 0.5: the game
-- draws its pixel art at 2x on a 1080p canvas, so 0.5 shows it at native pixel size.
local core = require("runtime.core")
local G = require("runtime.gfx")
local I = require("runtime.input")
local K = I.KEY

local T = {}
T.S = 0.5
T.c = {
  -- original palette (prefab colors)
  ink = 0x4d22cfff, inkSoft = 0x878787ff, lilac = 0xab9ed7ff, sky = 0x5bb4e1ff,
  paper = 0xfcf0ffff, paper2 = 0xfdf8fdff, white = 0xffffffff,
  pink = 0xff9fd6ff, pinkDark = 0xe0559fff, lilacDark = 0x6c4fd1ff, mint = 0x8ff0c8ff,
  yellow = 0xfff08aff, red = 0xe75252ff, desk = 0x9fc8f0ff, shadow = 0x00000050, dim = 0x000000a0,
  focus = 0xffd93bff, ame = 0xffffffff, pi = 0xdff3ffff, sep = 0xab9ed7ff,
}
local c = T.c

function T.panel(x, y, w, h, fill)
  if not G.draw9("InputFieldBackground", x, y, w, h, T.S) then
    G.rect(x, y, w, h, fill or c.paper)
    G.frame_rect(x, y, w, h, c.lilac)
  end
end

-- window frame (windowbase_active, 9-slice); returns the content rect
local lastWin = nil
function T.window(x, y, w, h, title, icon)
  if not G.draw9("windowbase_active", x, y, w, h, T.S) then
    G.rect(x, y, w, h, c.paper); G.frame_rect(x, y, w, h, c.ink)
  end
  if icon then G.draw(icon, x + 6, y + 5, { fit = { 11, 11 } }) end
  G.text(title or "", x + (icon and 20 or 8), y + 5, c.ink, 1, w - 60, 1)
  lastWin = { x = x, y = y, w = w, h = h }
  return x + 4, y + 22, w - 10, h - 27
end

-- the window's close button (button_close sprite at the title bar's right end)
function T.close(id)
  local wnd = lastWin
  if not wnd then return false end
  local bx, by = wnd.x + wnd.w - 19, wnd.y + 4
  local focused = I.focusable(id, bx - 2, by - 2, 16, 16)
  local pressed = I.touching_in(bx - 4, by - 4, 20, 20)
  if not G.draw("button_close", bx, by + (pressed and 1 or 0), { scale = T.S }) then G.text("x", bx + 2, by, c.white) end
  if focused then G.frame_rect(bx - 2, by - 2, 14, 14, c.focus, 1) end
  if I.tapped(bx - 6, by - 6, 22, 22) or I.activated(id) then
    if T.click_se then T.click_se() end
    return true
  end
  return false
end

local function focus_ring(x, y, w, h)
  G.frame_rect(x - 2, y - 2, w + 4, h + 4, c.focus, 2)
end
T.focus_ring = focus_ring

-- button(id, x, y, w, h, label, opts) -> true when tapped or activated with A (BaseButton art)
function T.button(id, x, y, w, h, label, o)
  o = o or {}
  local pressed = I.touching_in(x, y, w, h)
  local focused = I.focusable(id, x, y, w, h)
  local spr = o.disabled and "BaseButtonDisabled" or (pressed and "BaseButtonPressed" or (focused and "BaseButtonHovered" or "BaseButton"))
  if o.fill or o.flat then
    G.rect(x, y, w, h, o.disabled and 0xe8e2f0ff or (o.fill or c.paper))
    G.frame_rect(x, y, w, h, o.border or c.lilac)
  elseif not G.draw9(spr, x, y, w, h, T.S) then
    G.rect(x, y, w, h, c.white); G.frame_rect(x, y, w, h, c.ink)
  end
  local off = pressed and 1 or 0
  if o.icon then
    local s = o.iconSize or (h - 8)
    G.draw(o.icon, x + off + (o.iconX or 4), y + off + (h - s) / 2, { fit = { s, s } })
  end
  if label and label ~= "" then
    local col = o.disabled and c.inkSoft or (o.color or c.ink)
    local lx = x + off + (o.icon and (o.iconSize or (h - 8)) + 8 or 6)
    if o.center then
      G.text_center(label, x + off + w / 2, y + off + (h - G.LH) / 2, col, 1, w - 8)
    else
      local _, th = G.measure(label, 1, w - (lx - x) - 4, o.maxLines or 3)
      G.text(label, lx, y + off + math.max(2, (h - th) / 2), col, 1, w - (lx - x) - 4, o.maxLines or 3)
    end
  end
  if focused then focus_ring(x, y, w, h) end
  if o.disabled then return false end
  if I.tapped(x, y, w, h) or I.activated(id) then
    if T.click_se then T.click_se() end
    return true
  end
  return false
end

-- desktop icon: original icon art, white label with a dark outline like Windose
function T.icon(id, x, y, sprite, label, badge)
  local w, h = 64, 56
  local focused = I.focusable(id, x, y, w, h)
  local pressed = I.touching_in(x, y, w, h)
  if pressed or focused then G.rect(x + 8, y, 48, 52, 0x4d22cf40) end
  if not G.draw(sprite, x + 16, y + 2 + (pressed and 1 or 0), { fit = { 32, 32 } }) then
    G.rect(x + 16, y + 2, 32, 32, c.lilac)
  end
  local lw = G.measure(label)
  local lx = math.max(1, math.min(x + (w - lw) / 2, 319 - lw))   -- keep long labels on screen
  -- a 1 px outline around this thin pixel font merges the letters ("m" became a blob): ink text on
  -- a soft white plate reads cleanly over the patterned wallpaper
  lx = math.floor(lx)
  G.rect(lx - 2, y + 36, lw + 4, G.LH + 1, 0xffffffb0)
  G.text(label, lx, y + 37, c.ink, 1, w + 20, 1)
  if badge and badge > 0 then
    G.rect(x + 44, y, 14, 12, c.red); G.frame_rect(x + 44, y, 14, 12, c.white)
    G.text_center(tostring(badge), x + 51, y + 1, c.white)
  end
  if focused then focus_ring(x + 6, y, 52, 54) end
  return I.tapped(x, y, w, h) or I.activated(id)
end

-- vertical scroll state helper: drag with stylus, Circle Pad scrolls
function T.scroller(state, x, y, w, h, contentH)
  state.y = state.y or 0
  -- drag with the stylus; released, the list keeps the flick speed and slows down like a Unity
  -- ScrollRect (inertia on, decelerationRate 0.135 per second)
  if I.touching_in(x, y, w, h) then
    state.y = state.y - I.drag_dy
    state.v = -I.drag_dy
    state.anim = nil
  elseif state.v and state.v ~= 0 then
    state.y = state.y + state.v
    state.v = math.abs(state.v) > 0.3 and state.v * 0.967 or 0
  end
  if I.isheld(K.CUP) then state.y = state.y - 4 end
  if I.isheld(K.CDOWN) then state.y = state.y + 4 end
  local maxY = math.max(0, contentH - h)
  -- JineView2D.ScrollToLatest: when the content grows and the list is near the bottom (within
  -- 15 %) or short (state.short), it scrolls down in 0.15 s (InQuad); otherwise the ToBottom
  -- button appears (state.below) and does it when pressed (T.scroll_to_bottom)
  if state.stick_bottom then
    if state.lastMax and maxY > state.lastMax + 0.5 then
      local fromBottom = state.lastMax - state.y
      if state.short or fromBottom <= 0.15 * math.max(state.lastMax, 1) then
        state.anim = { from = state.y, t0 = core.now() }
      else
        state.below = true
      end
    end
    if state.anim then
      local k = math.min(1, (core.now() - state.anim.t0) / 0.15)
      state.y = state.anim.from + (maxY - state.anim.from) * k * k
      if k >= 1 then state.anim = nil end
    end
    if state.y >= maxY - 0.5 then state.below = false end
  end
  if state.y < 0 or state.y > maxY then state.v = 0 end
  state.y = math.max(0, math.min(maxY, state.y))
  state.lastMax = maxY
  if contentH > h then
    local bh = math.max(12, h * h / contentH)
    local by = y + (h - bh) * (state.y / maxY)
    G.rect(x + w - 4, y, 4, h, 0xcdebfcff)
    G.rect(x + w - 4, by, 4, bh, 0xea9fe8ff)
  end
  return state.y
end

function T.scroll_to_bottom(state)
  state.anim, state.below, state.v = { from = state.y or 0, t0 = core.now() }, false, 0
end

function T.dim(w) G.rect(0, 0, w or 400, 240, c.dim) end

-- port-only UI strings (texts the original doesn't have) in the three languages
local LANG_KEY = { JP = "ja", EN = "en" }
function T.tr(t)
  local cur = Settings and Settings.CurrentLanguage and Settings.CurrentLanguage.Value
  return t[LANG_KEY[cur] or "es"] or t.es
end
-- the drug insert window (the game has no SystemText for its title)
T.YAKUJO_TITLE = { es = "Prospecto", en = "Package Insert", ja = "添付文書" }
-- SystemText by id with a fallback
function T.st(id, fallback)
  local ok, s = pcall(NgoEx.SystemTextFromType, id, Settings.CurrentLanguage.Value)
  return (ok and type(s) == "string" and s ~= "") and s or fallback
end

return T
