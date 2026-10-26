-- Stream on two screens.
-- TOP: the broadcast (background, Ame/Chouten animation, typewriter subtitles, title, viewers).
-- BOTTOM: live chat. Hold a comment = pause (the original mouse hover), tap a superchat = pick it
-- for reading, tap / swipe-left a normal comment = delete it. R = speed, SELECT = skip, A = next line.
local core = require("runtime.core")
local G = require("runtime.gfx")
local I = require("runtime.input")
local T = require("ui.theme")
local K = I.KEY
local c = T.c

local M = {}
local scroll = { stick_bottom = true }

-- the Live controller lives as long as a broadcast window is open
local function ensure_live()
  local open, newest = false, 0
  for _, w in EACH(WindowManager.windows) do
    if w.kind == "live" then open = true; newest = math.max(newest, w.opened or 0) end
  end
  -- a stream window (re)opened after the current controller started = a new broadcast
  local cur = core.views.Live
  if open and cur and newest > (rawget(cur, "_started") or 0) then
    core.views.Live, core.components.Live = nil, nil
  end
  if open and not core.views.Live then
    local live = NEW("Live")
    rawset(live, "_started", core.now())
    core.views.Live = live
    core.components.Live = live
    spawn(function() live:Awake() end)
  elseif not open and core.views.Live then
    core.views.Live = nil
    core.components.Live = nil
    TaskbarManager:SetTaskbarInteractive(true)
  end
  return core.views.Live
end
M.ensure_live = ensure_live

function M.update(dt)
  local live = ensure_live()
  if not live then return end
  if I.pressed(K.R) then live:ToggleSpeed() end
  if I.pressed(K.L) then live:DownSpeed() end
  if I.pressed(K.SELECT) then live:Skip() end
  if I.pressed(K.A) and not I.focus_visible then live:NextSerihu() end
end

local function lang() return Settings.CurrentLanguage.Value end
local function st(id, fallback)
  local ok, s = pcall(NgoEx.SystemTextFromType, id, lang())
  return (ok and type(s) == "string" and s ~= "") and s or fallback
end

-- thousands separator like the original viewer count
local function num(n)
  local s = tostring(math.floor(n or 0))
  return (s:reverse():gsub("(%d%d%d)", "%1."):reverse():gsub("^%.", ""))
end

-- TOP (App_Live/Body): "▶ live" bar with the title (HaisinTitle, ink) and viewers / start day
-- (HaisinDetail, gray), then eizo: bg_stream + Ame, red progress Slider, jimaku box #4d22cfcc
function M.draw_top()
  local live = core.views.Live
  G.rect(0, 0, 400, 240, c.paper2)
  if not live then return end
  -- header bar of the haisin page
  G.rect(0, 0, 400, 13, c.white)
  G.rect(0, 13, 400, 1, 0xf3e3f5ff)
  G.text("▶", 4, 1, c.red); G.text("live", 14, 1, c.red)
  local detail = num(live.watcher) .. " " .. st("Haisin_Watching_Number", "viendo")
  local dw = G.measure(detail)
  G.text(live.haisinTitle or "", 44, 1, c.ink, 1, 396 - dw - 52, 1)
  G.text(detail, 396 - dw, 1, c.inkSoft, 1, 160, 1)
  -- eizo (the broadcast picture)
  local ex, ey, ew, eh = 26, 14, 348, 226
  G.clip(ex, ey, ew, eh)
  G.draw(live.bg or "bg_stream", ex, ey, { w = ew, h = eh })
  if live.noChair then G.draw("bg_stream_no_chair", ex, ey, { w = ew, h = eh }) end
  local a = live.anim
  if live.endCard then
    G.draw("stream_cho_end", ex, ey, { w = ew, h = eh })
  elseif a and not live.hideGirl and not G.play(a.name, core.now() - a.t0, ex, ey) then
    G.play("stream_cho_akaruku", core.now() - a.t0, ex, ey)
  end
  -- progress Slider (Fill #e75252) near the bottom of the picture
  local sc = live.NowPlaying
  if sc and live.scenarioLength and live.scenarioLength > 0 then
    local k = math.max(0, math.min(1, 1 - sc.playing.Count / live.scenarioLength))
    G.rect(ex + 10, ey + eh - 6, ew - 20, 2, 0xffffff90)
    G.rect(ex + 10, ey + eh - 6, (ew - 20) * k, 2, c.red)
  end
  -- jimaku: purple translucent box centered at the bottom, white typewriter text
  local j = live.jimaku
  if j and j.text ~= "" then
    local shown = j.text
    if j.dur > 0 and not j.skip then
      local n = math.floor((core.now() - j.t0) / j.dur * j.len)
      local cut = utf8.offset(j.text, n + 1)
      if cut then shown = j.text:sub(1, cut - 1) end
    end
    local tw, th = G.measure(j.text, 1, ew - 40)
    local bw, bh = tw + 12, th + 6
    local bx, by = ex + (ew - bw) / 2, ey + eh - 12 - bh
    G.rect(bx, by, bw, bh, 0x4d22cfcc)
    G.text(shown, bx + 6, by + 3, c.white, 1, ew - 40)
  end
  -- anti (kusoripu) bubble: #fcf0ff box with the black kusoripu icon
  if live.anti then
    local _, th = G.measure(live.anti, 1, 150)
    local h = math.max(28, th + 8)
    G.rect(ex + 8, ey + 8, 182, h, c.paper)
    G.draw("icon_kusoripu_black", ex + 12, ey + 8 + (h - 24) / 2, { fit = { 24, 24 } })
    G.text(live.anti, ex + 40, ey + 8 + (h - th) / 2, c.ink, 1, 146)
  end
  G.unclip()
  -- side margins of the page
  if sc and sc.isGensoku and sc.isGensoku.Value then G.text("II", 8, 20, c.lilac) end
end

-- BOTTOM: chat (Scroll View with LiveComment rows: CommentIcon + ink text, trash icon on bad
-- comments), "Leer los comentarios ▶" + yomuCommentBox, speed button and ▶SKIP (BaseButton)
local ROW_W = 296
local function comment_height(cm)
  if not cm.h then
    local _, h = G.measure(cm.text, 1, ROW_W - 34)
    cm.h = math.max(18, h + 6)
  end
  return cm.h
end

function M.draw(win, x0, y0, w0, h0)
  local live = core.views.Live
  G.rect(0, 0, 320, h0, c.paper2)
  if not live then return end
  local listX, listY, listW = 4, 4, 312
  local listH = h0 - 4 - 76
  G.rect(listX, listY, listW, listH, c.white)
  G.frame_rect(listX, listY, listW, listH, 0xf3e3f5ff)
  local total = 0
  for _, cm in ipairs(live.comments) do total = total + comment_height(cm) end
  local sy = T.scroller(scroll, listX, listY + 1, listW, listH - 2, total)
  local hovering = false
  G.clip(listX, listY + 1, listW, listH - 2)
  local y = listY + 1 - sy
  for i, cm in ipairs(live.comments) do
    local h = comment_height(cm)
    if y + h > listY and y < listY + listH then
      local rx = listX + 2
      if cm.deleted then
        G.draw("icon_trash_can", rx + 4, y + (h - 12) / 2, { fit = { 10, 12 } })
        G.text("—", rx + 22, y + 3, c.inkSoft)
      else
        if cm.pickable or cm.color then G.rect(rx, y, ROW_W, h - 1, cm.color or 0xfff4d6ff) end
        if cm.done then G.rect(rx, y, ROW_W, h - 1, 0xe8e2f0c0) end
        G.draw("CommentIcon", rx + 4, y + (h - 8) / 2, { fit = { 8, 8 } })
        G.text(cm.text, rx + 18, y + 3, cm.done and c.inkSoft or c.ink, 1, ROW_W - 34)
        if (cm.p.isBadComment or cm.p.delta and cm.p.delta < 0) and not cm.done then
          G.draw("icon_trash_can", rx + ROW_W - 14, y + (h - 12) / 2, { fit = { 10, 12 } })
        end
      end
      G.rect(rx, y + h - 1, ROW_W, 1, 0xf3e3f5ff)
      if not cm.done then
        if I.touching_in(rx, math.max(y, listY), ROW_W, h) then hovering = true end
        local id = "cm" .. i
        if I.focusable(id, rx, y, ROW_W, h) then T.focus_ring(rx, y, ROW_W, h) end
        local swipe = I.swiped(rx, math.max(y, listY), ROW_W, h)
        if I.tapped(rx, math.max(y, listY), ROW_W, h) or I.activated(id) or (swipe == "left" and not cm.pickable) then
          live:tapComment(cm)
        end
      end
    end
    y = y + h
  end
  G.unclip()
  live:hover(hovering)
  -- comments to be read (commentLabel + YomucommentParent)
  local ty = listY + listH + 3
  local label = live.isStartRead and st("Sysyem_StartRead", "…") or st("Sysyem_ReadComment", "Leer los comentarios ▶")
  G.text(label, 6, ty, c.lilac, 1, 308, 1)
  local by = ty + 13
  local grey = live.isStartRead
  if not G.draw("yomuCommentBox", 4, by, { w = 312, h = 34, tint = grey and 0xccccccff or nil, blend = grey and 0.3 or 0 }) then
    G.rect(4, by, 312, 34, c.paper2)
  end
  for k = 1, 2 do
    local p = live.tray[k]
    if p then G.text(p.nakami, 8 + (k - 1) * 160, by + 3, c.ink, 1, 146, 2) end
  end
  -- Button (speed) + SkipButton
  local bty = by + 37
  local sp = (live.Speed or 0) + 1
  if T.button("lv_speed", 4, bty, 206, 18, st("HaishinSpeed_" .. sp, "x" .. sp), { center = true, disabled = live._lockSpeed }) then
    live:ToggleSpeed()
  end
  if T.button("lv_skip", 216, bty, 100, 18, "▶SKIP", { center = true }) then live:Skip() end
end

return M
