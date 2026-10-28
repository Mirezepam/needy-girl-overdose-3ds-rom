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

local opened_t, opened_win = 0, nil
local function entry(d)
  local e = cache[d]
  -- texts are resolved in the current language; a language change rebuilds them
  if e and e.lang == Settings.CurrentLanguage.Value then return e end
  local born = e and e.born
  local dr = NEW("TweetDrawable", 1, d)
  e = { text = NgoEx.GetTweetBody(dr, lang()), fav = d.FavNumber or 0, rt = d.RtNumber or 0, omote = d.IsOmote, replies = {},
        day = d.day }
  -- PoketterCell2D.Show unfolds and fades new tweets in (not the ones already there on open)
  if core.now() - opened_t > 0.4 then e.born = core.now() end
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
  e.h = 6 + 12 + h + 4 + (e.image and 78 or 0) + 14
  for _, r in ipairs(e.replies) do
    local _, rh = G.measure(r, 1, W - 72)
    e.h = e.h + math.max(18, rh + 4) + 2
  end
  e.lang, e.born = Settings.CurrentLanguage.Value, e.born or born
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
-- PoketterCell: icon, account (#1139a1), body (#1303a6), picture, RT (#07781c) / fav star
-- (#7a7717), DAY n (#5b5f62), then the kusoreps with the arrow and the black kusoripu icon
local function account(omote)
  if omote then return T.st("Account_Omote", "@x_angelkawaii_x") end
  return T.st("Account_Ura_Name", "@raincandy_U")
end
local function num(n)
  local s = tostring(math.floor(n or 0))
  return (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end
local function draw_tweet(e, x, y, sel)
  G.rect(x, y, W, e.h - 2, sel and 0xfff4d6ff or c.white)
  G.rect(x, y + e.h - 3, W, 1, 0xe6e0f0ff)
  G.draw(e.omote and "icon_cho" or "icon_ame_ura", x + 4, y + 4, { fit = { 22, 22 } })
  G.text(account(e.omote), x + 30, y + 3, 0x1139a1ff, 1, W - 74, 1)
  if e.day then G.text("DAY " .. e.day, x + W - 40, y + 3, 0x5b5f62ff) end
  local th = G.text(e.text, x + 30, y + 16, 0x1303a6ff, 1, W - 40)   -- text() returns height, width
  local yy = y + 16 + th + 2
  if e.image then
    G.rect(x + 30, yy, 124, 74, 0x000000ff)
    G.draw(e.image, x + 92, yy + 37, { ax = 0.5, ay = 0.5, fit = { 124, 74 } })
    yy = yy + 78
  end
  G.draw("icon_retweet", x + 30, yy + 1, { fit = { 10, 10 } }); G.text(num(e.rt), x + 43, yy, 0x07781cff)
  G.draw("icon_star", x + 120, yy + 1, { fit = { 10, 10 } }); G.text(num(e.fav), x + 133, yy, 0x7a7717ff)
  yy = yy + 14
  for _, r in ipairs(e.replies) do
    G.draw("image_kusorep_arrow", x + 30, yy + 2, { fit = { 8, 10 } })
    G.draw("icon_kusoripu_black", x + 42, yy, { fit = { 16, 16 } })
    local rh = G.text(r, x + 62, yy + 2, 0x1303a6ff, 1, W - 72)
    yy = yy + math.max(18, rh + 4) + 2
  end
end

function M.draw(win, x0, y0, w0, h0)
  if opened_win ~= win then opened_win, opened_t = win, core.now() end
  local title = T.app_title(win.app, "Poketter")
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
  -- PoketterCell2D.Show: a new tweet first opens its space (DOScaleY 0 -> 1 in 1 s, pushing the
  -- older ones down) and then fades in (Fader2D 1 s)
  local function anim(e)
    if not e.born then return 1, 1 end
    local t = core.now() - e.born
    local q = math.min(1, t)
    return 1 - (1 - q) ^ 2, math.max(0, math.min(1, t - 1))
  end
  local list, total = {}, 0
  for i = n, math.max(1, n - 40), -1 do      -- newest first
    local d = hist.items[i]
    local e = entry(d)
    local open, alpha = anim(e)
    local hh = math.floor((e.h + 2) * open + 0.5)
    list[#list + 1] = { d = d, e = e, hh = hh, alpha = alpha }
    total = total + hh
  end
  if pm._tweetQueue.Count > 0 then
    G.draw("icon_loading_poketter_00" .. (math.floor(core.now() * 10) % 8), x + w / 2 - 8, y + 2, { fit = { 16, 16 } })
  end
  local top = pm._tweetQueue.Count > 0 and 18 or 2
  local sy = T.scroller(scroll, x, y + top, w, h - top, total)
  G.clip(x, y + top, w, h - top)
  local yy = y + top - sy
  for i, it in ipairs(list) do
    if it.alpha <= 0 then
      -- still opening its space: nothing drawn yet
    elseif not (yy + it.e.h > y and yy < y + h) then
      -- off view: still reachable with the D-pad, which scrolls it in
      I.focusable("tw" .. i, x + 4, yy, W, it.e.h)
      if I.focus_visible and I.focus_id == "tw" .. i then T.reveal(scroll, yy, it.e.h, y + top, h - top) end
    else
      if I.focus_visible and I.focus_id == "tw" .. i then T.reveal(scroll, yy, it.e.h, y + top, h - top) end
      if it.alpha < 1 then
        G.push(0, 0, 1, 1 - (1 - it.alpha) ^ 2)
        draw_tweet(it.e, x + 4, yy, selected == it.d)
        G.pop()
      else
        draw_tweet(it.e, x + 4, yy, selected == it.d)
      end
      local pick = I.tapped(x + 4, math.max(yy, y + top), W, it.e.h)
      if I.focusable("tw" .. i, x + 4, yy, W, it.e.h) then
        T.focus_ring(x + 4, yy, W, it.e.h - 2)
        if I.activated("tw" .. i) then pick = true end
      end
      if pick then
        selected = it.d
        if it.e.image == "MV_thumbnail" then M.play_mv() end
      end
    end
    yy = yy + it.hh
  end
  G.unclip()
end

M.entry, M.draw_tweet, M.W = entry, draw_tweet, W

-- PoketterCell.PlayMV: the INTERNET OVERDOSE video on the top screen; the clip has no sound, the
-- song starts 2 s in on the BGM channel and the 8-bit version loops once the 224 s are over
local mv_running = false
function M.play_mv()
  if mv_running then return end
  mv_running = true
  spawn(function()
    AudioManager:StopBgm()
    local w = WindowManager:open("MV")
    core.wait_ms(2000)
    AudioManager:PlayBgmByType("BGM_InternetOverdose", false)
    local t0 = core.now()
    while core.now() - t0 < 222 and WindowManager:find("MV") do core.wait_ms(250) end
    if WindowManager:find("MV") then WindowManager:Close(w) end
    AudioManager:PlayBgmByType("BGM_InternetOverdose8bit", true)
    mv_running = false
  end)
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
