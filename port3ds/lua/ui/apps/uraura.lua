-- Uratter window of Ending_Happy (App_uraura: EndingHappyUraUra / EndingUraUraFollowers /
-- EndingUraUraTweets). First the follower list of Ame's account, with the secret account
-- ("Dark@...") blinking under a hint balloon; tapping it shows that account: five tweets fading
-- in every 2.2 s and a Follow button that ends in "blocked" and the game shutting down.
local core = require("runtime.core")
local G = require("runtime.gfx")
local I = require("runtime.input")
local T = require("ui.theme")
local c = T.c

local M = {}
local state = setmetatable({}, { __mode = "k" })

local function lang() return Settings.CurrentLanguage.Value end
local function et(id)
  local s = NgoEx.EndingTextFromType(id, lang())
  return (s ~= NULL and s) or id
end

local function background(x, y, w, h)
  G.clip(x, y, w, h)
  for ty = y, y + h, 183 do
    for tx = x, x + w, 183 do
      if not G.draw("result_bg_tile", tx, ty, { w = 183, h = 183 }) then G.rect(x, y, w, h, 0xbb99ddff) end
    end
  end
  G.unclip()
end

local function user_row(x, y, icon, name, w)
  G.draw(icon, x, y, { fit = { 22, 22 } })
  G.text(name, x + 28, y + 5, c.ink, 1, w - 32, 1)
end

local function followers(st, x, y, w, h)
  G.rect(x + 6, y + 4, w - 12, h - 8, c.paper)
  user_row(x + 14, y + 10, "icon_ame", T.st("Account_Ura_Name", "@raincandy_U"), w - 40)
  if not G.draw9("BaseButtonDisabled", x + w - 70, y + 10, 56, 20, 0.5) then G.rect(x + w - 70, y + 10, 56, 20, 0xe8e2f0ff) end
  G.text_center(et("ZZZ_Ending_Happy_Follow"), x + w - 42, y + 14, c.inkSoft)
  local label = lang() == "JP" and "フォロワー" or (NgoEx.StatusTextFromType("Status_Follower", lang()))
  G.text_center(label ~= NULL and label or "Seguidores", x + w / 2, y + 42, c.ink)
  G.rect(x + w / 2 - 92, y + 56, 184, 1, 0x8ad4ffff)
  user_row(x + 30, y + 66, "icon_kusoripu_yellow", et("Ending_Happy_Follower3"), w - 60)
  user_row(x + 30, y + 94, "icon_kusoripu_black", et("Ending_Happy_Follower2"), w - 60)
  -- the secret account: tappable, with the blinking hint balloon (_uraUraHint yoyo fade)
  local ry = y + 122
  user_row(x + 30, ry, "icon_ame_ura", et("Ending_Happy_Follower1"), w - 60)
  local a = 0.5 + 0.5 * math.sin((core.now() - st.t0) * math.pi)
  G.draw9("balloon", x + w - 120, ry - 30, 104, 26, 0.5, { alpha = math.abs(a), tint = 0xcdebfcff })
  G.text_center("!", x + w - 68, ry - 25, c.ink)
  if I.focusable("ura_acc", x + 26, ry - 2, w - 52, 26) then T.focus_ring(x + 26, ry - 2, w - 52, 26) end
  if I.tapped(x + 26, ry - 2, w - 52, 26) or I.activated("ura_acc") then
    AudioManager:PlaySeByType("SE_click")
    st.phase, st.t1 = "tweets", core.now()
  end
end

local function tweets(st, x, y, w, h)
  G.rect(x + 6, y + 4, w - 12, h - 8, c.paper)
  local name = et("Ending_Happy_Follower1")
  user_row(x + 14, y + 10, "icon_ame_ura", name, w - 100)
  if T.button("ura_follow", x + w - 72, y + 8, 58, 22, et("ZZZ_Ending_Happy_FollowRequest"), { center = true, disabled = st.requested }) then
    st.requested = true
    spawn(function()
      AudioManager:PlaySeByType("SE_piporo")
      core.wait_ms(Constants.MIDDLE)
      AudioManager:PlaySeByType("SE_Error")
      st.blocked = true
      core.wait_ms(Constants.MIDDLE)
      NotificationManager:osimai()
      AchievementStatsUpdater.UpdateStats("Ending_Happy")
    end)
  end
  -- five tweets, one more every 2.2 s, each fading in
  local t = core.now() - st.t1
  local yy = y + 38
  for i = 1, 5 do
    local a = math.max(0, math.min(1, (t - (i - 1) * 2.2) / 2.2))
    if a <= 0 then break end
    local body = et("Ending_Happy_UrauraTweet00" .. i)
    local _, th = G.measure(body, 1, w - 60)
    G.rect(x + 10, yy, w - 20, th + 20, 0xffffff00 | math.floor(a * 255))
    G.draw("icon_ame_ura", x + 14, yy + 3, { fit = { 16, 16 }, alpha = a })
    G.text(name, x + 34, yy + 2, (0x4d22cf00 | math.floor(a * 255)), 1, w - 60, 1)
    G.text(body, x + 34, yy + 15, (0x4d22cf00 | math.floor(a * 255)), 1, w - 60)
    yy = yy + th + 24
  end
  if st.blocked then
    G.rect(x + 6, y + 4, w - 12, h - 8, 0x000000a0)
    -- the blocked cover: Ending_Normal_System002 and Poketter_Blocked_Description in ink
    T.panel(x + 30, y + h / 2 - 26, w - 60, 52, c.white)
    G.text_center(T.st("Ending_Normal_System002", ""), x + w / 2, y + h / 2 - 20, 0x4d22cfff, 1, w - 70)
    G.text_center((T.st("Poketter_Blocked_Description", ""):gsub("^%s+", "")), x + w / 2, y + h / 2 + 2, 0x4d22cfff, 1, w - 70)
  end
end

function M.draw(win, x0, y0, w0, h0)
  local st = state[win]
  if not st then st = { phase = "followers", t0 = core.now() }; state[win] = st end
  local x, y, w, h = T.window(x0 + 2, y0 + 2, w0 - 4, h0 - 2, T.app_title("Uratter"), "icon_taskbar_poketter")
  background(x, y, w, h)
  if st.phase == "followers" then followers(st, x, y, w, h) else tweets(st, x, y, w, h) end
end

-- test harness: what a player would tap next
function M.bot_step(win)
  local st = state[win]
  if not st then return end
  if st.phase == "followers" then st.phase, st.t1 = "tweets", core.now()
  elseif not st.requested and core.now() - st.t1 > 11 then
    st.requested = true
    spawn(function()
      st.blocked = true
      NotificationManager:osimai()
      AchievementStatsUpdater.UpdateStats("Ending_Happy")
    end)
  end
end

-- top screen: Ame's room stays dark while the secret account is open
function M.draw_top()
  G.rect(26, 14, 348, 226, 0x000000c0)
  return false
end

return M
