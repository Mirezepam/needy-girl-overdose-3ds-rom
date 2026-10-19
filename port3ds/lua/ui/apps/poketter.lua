-- Poketter (the in-game Twitter). Bottom: timeline you scroll and tap. Top: the selected tweet
-- and its picture at full size. Also implements PoketterView2D.shootTweetAll (queue -> timeline).
local core = require("runtime.core")
local G = require("runtime.gfx")
local I = require("runtime.input")
local T = require("ui.theme")
local c = T.c

local M = { icon = "icon_taskbar_poketter" }
local scroll = {}
local cache = setmetatable({}, { __mode = "k" })
local selected = nil
local W = 290

local function lang() return Settings.CurrentLanguage.Value end

local function entry(d)
  local e = cache[d]
  if e then return e end
  local dr = NEW("TweetDrawable", 1, d)
  e = { text = NgoEx.GetTweetBody(dr, lang()), fav = d.FavNumber or 0, rt = d.RtNumber or 0, omote = d.IsOmote, replies = {} }
  if e.text == NULL then e.text = "" end
  local img = dr.ImageId
  if type(img) == "string" and G.exists(img) then e.image = img end
  if d.kusoReps and d.kusoReps ~= NULL then
    for _, k in EACH(d.kusoReps) do
      local kd = NEW("KusoRepDrawable", 1, k)
      local body = NgoEx.GetKusoRepBody(kd, lang())
      if body ~= NULL and body ~= "" then e.replies[#e.replies + 1] = body end
    end
  end
  if d.kusoRepString and d.kusoRepString ~= NULL then
    for _, s in EACH(d.kusoRepString) do e.replies[#e.replies + 1] = s end
  end
  local _, h = G.measure(e.text, 1, W - 40)
  e.h = h + 24 + (e.image and 16 or 0)
  for _, r in ipairs(e.replies) do
    local _, rh = G.measure(r, 1, W - 60)
    e.h = e.h + rh + 4
  end
  cache[d] = e
  return e
end

-- ------------------------------------------------------------------ view used by the game code
local view = { running = false }
core.views.PoketterView2D = view
function view:shootTweetAll()
  local pm = PoketterManager
  if pm._tweetQueue.Count == 0 or pm.isShootRunning.Value then return end
  pm.isShootRunning.Value = true
  spawn(function()
    while pm._tweetQueue.Count >= 1 do
      NgoEvent.DelaySkippable(Constants.FAST)
      local tw = pm:AddHistoryFromQueue()
      AudioManager:PlaySeByType("SE_tweet")
      scroll.y = 0
      selected = tw
      core.wait_ms(300)
    end
    pm.isShootRunning.Value = false
  end)
end
function view:Click() end
-- PoketterView: while a Poketter / Result window is open, new tweets are shot right away
local hook
hook = core.poll(function()
  if not rawget(PoketterManager, "_tweetQueue") then return end   -- managers not booted yet
  hook:Dispose()
  PoketterManager.OnAddQueue:Subscribe(function()
    for _, w in EACH(WindowManager.windows) do
      if w.kind == "poketter" then spawn(function() view:shootTweetAll() end) return end
    end
  end)
end)

-- ------------------------------------------------------------------ draw
local function draw_tweet(e, x, y, sel)
  G.rect(x, y, W, e.h - 2, sel and 0xfff4d6ff or c.white)
  G.frame_rect(x, y, W, e.h - 2, 0xd8d0ecff)
  G.draw(e.omote and "icon_ame" or "icon_ame_ura", x + 4, y + 4, { fit = { 22, 22 } })
  G.text(e.omote and "@chouten_KAWAII" or "@ame_ura", x + 30, y + 3, c.inkSoft)
  local _, th = G.text(e.text, x + 30, y + 14, c.ink, 1, W - 40)
  local yy = y + 14 + th
  if e.image then G.text("▣ imagen (arriba)", x + 30, yy, c.lilacDark); yy = yy + 14 end
  G.draw("icon_heart", x + 30, yy, { fit = { 9, 9 } }); G.text(tostring(e.fav), x + 42, yy, c.pinkDark)
  G.draw("icon_retweet", x + 100, yy, { fit = { 9, 9 } }); G.text(tostring(e.rt), x + 112, yy, c.mint)
  yy = yy + 12
  for _, r in ipairs(e.replies) do
    local _, rh = G.text("↳ " .. r, x + 40, yy, c.inkSoft, 1, W - 60)
    yy = yy + rh + 4
  end
end

function M.draw(win, x0, y0, w0, h0)
  local title = win.app == "Uratter" and "Uratter" or "Poketter"
  local x, y, w, h = T.window(x0 + 2, y0 + 2, w0 - 4, h0 - 2, title, "icon_taskbar_poketter")
  if win.closeable and T.close("pk_close") then
    WindowManager:Close(win) return
  end
  -- App_Poketter: Bg2 = result_bg_tile tiled (tinted #fcf0ff), Bg = PoketterNakami2 white panel
  -- with the white "poketter" logo above it
  G.clip(x, y, w, h)
  for ty = y, y + h, 183 do
    for tx = x, x + w, 183 do
      if not G.draw("result_bg_tile", tx, ty, { w = 183, h = 183, tint = 0xfcf0ffff, blend = 0 }) then
        G.rect(x, y, w, h, 0xbb99ddff)
      end
    end
  end
  G.unclip()
  G.text(win.app == "Uratter" and "uratter" or "poketter", x + 8, y + 2, c.white)
  if not G.draw9("PoketterNakami2", x + 2, y + 16, w - 4, h - 18, 0.5) then G.rect(x + 2, y + 16, w - 4, h - 18, c.white) end
  y, h = y + 16, h - 18
  local pm = PoketterManager
  if pm.isBlocked and pm.isBlocked.Value then
    G.text(NgoEx.SystemTextFromType("Poketter_Blocked_Header", lang()), x + 8, y + 8, c.red, 1, w - 16)
    return
  end
  if pm.isDeleted and pm.isDeleted.Value then
    G.text(NgoEx.SystemTextFromType("Poketter_Deleted_Header", lang()), x + 8, y + 8, c.red, 1, w - 16)
    return
  end
  local hist = pm.history
  local n = hist and hist.n or 0
  local list, total = {}, 0
  for i = n, math.max(1, n - 40), -1 do      -- newest first
    local d = hist.items[i]
    local e = entry(d)
    list[#list + 1] = { d = d, e = e }
    total = total + e.h + 2
  end
  if pm._tweetQueue.Count > 0 then
    G.draw("icon_loading_poketter_00" .. (math.floor(core.now() * 10) % 8), x + w / 2 - 8, y + 2, { fit = { 16, 16 } })
  end
  local top = pm._tweetQueue.Count > 0 and 18 or 2
  local sy = T.scroller(scroll, x, y + top, w, h - top, total)
  G.clip(x, y + top, w, h - top)
  local yy = y + top - sy
  for i, it in ipairs(list) do
    if yy + it.e.h > y and yy < y + h then
      draw_tweet(it.e, x + 4, yy, selected == it.d)
      if I.tapped(x + 4, math.max(yy, y + top), W, it.e.h) then selected = it.d end
      if I.focusable("tw" .. i, x + 4, yy, W, it.e.h) then
        T.focus_ring(x + 4, yy, W, it.e.h - 2)
        if I.activated("tw" .. i) then selected = it.d end
      end
    end
    yy = yy + it.e.h + 2
  end
  G.unclip()
end

-- top screen: the selected tweet, picture at full size
function M.draw_top(win)
  if not selected then return false end
  local e = entry(selected)
  if e.image and G.exists(e.image) then
    G.rect(26, 14, 348, 226, 0x000000e0)
    G.draw(e.image, 200, 120, { ax = 0.5, ay = 0.5, fit = { 340, 180 } })
    T.panel(30, 200, 340, 36, c.white)
    G.text(e.text, 34, 203, c.ink, 1, 332, 2)
    return true
  end
  return false
end

return M
