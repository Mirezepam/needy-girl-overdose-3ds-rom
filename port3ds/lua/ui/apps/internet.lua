-- Internet / 2ch board / ego-search results: list on the bottom, selected entry big on top.
local core = require("runtime.core")
local G = require("runtime.gfx")
local I = require("runtime.input")
local T = require("ui.theme")
local c = T.c

local M = { icon = "icon_desktop_internet" }
local scroll = {}
local selected

-- KitsuneView.Jien(): posts the player's own thread replies on the board
local board = { posts = {} }
core.views.KitsuneView = {
  Jien = function(_, text) board.posts[#board.posts + 1] = text; selected = text end,
  -- horror day 3 opens the board with the first / second / third thread
  UpdateContents = function(_, num)
    if num and num >= 0 then
      board.forced = ({ [0] = "Horror_Day3_first", "Horror_Day3_second" })[num] or "Horror_Day3_third"
    end
  end,
  CleanThread = function() board.posts = {} end,
}
-- TinderView: shuffled profiles, Nope slides to the next one, Like runs the InternetDeai action,
-- whose event calls OnChoosed (the match picture)
local OTOKO = { "tinder_dog", "tinder_beetle", "tinder_cameraman", "tinder_gorilla", "tinder_horse", "tinder_robot" }
local dinder = { order = nil, i = 1, slide = nil, matched = false }
local function dinder_reset()
  local o = {}
  for _, s in ipairs(OTOKO) do table.insert(o, math.random(#o + 1), s) end
  dinder.order, dinder.i, dinder.slide, dinder.matched = o, 1, nil, false
end
core.views.TinderView = { OnChoosed = function() dinder.matched = true end }

local function dinder_profile()
  if not dinder.order then dinder_reset() end
  return dinder.order[(dinder.i - 1) % #dinder.order + 1], dinder.order[dinder.i % #dinder.order + 1]
end

local function draw_dinder(win, x, y, w, h)
  if rawget(win, "dinder_open") == nil then rawset(win, "dinder_open", true); dinder_reset() end
  G.rect(x, y, w, h, c.white)
  local cur, nxt = dinder_profile()
  local off = 0
  if dinder.slide then
    off = (core.now() - dinder.slide) / 0.8
    if off >= 1 then dinder.slide, dinder.i, off = nil, dinder.i + 1, 0 end
  end
  -- small preview here; the big profile is on the top screen
  G.draw(nxt, x + w / 2, y + 60, { ax = 0.5, ay = 0.5, fit = { 110, 110 } })
  G.draw(dinder.matched and "tinder_match" or cur, x + w / 2 - off * 320, y + 60, { ax = 0.5, ay = 0.5, fit = { 110, 110 } })
  local busy = dinder.slide ~= nil or dinder.matched
  if T.button("dinder_nope", x + 16, y + h - 34, (w - 48) / 2, 26, T.st("Dinder_Nope", "Nope"), { center = true, disabled = busy }) then
    AudioManager:PlaySeByType("SE_kuraiSelect")
    dinder.slide = core.now()
  end
  local st = CommandManager.commandStatus and CommandManager.commandStatus.Value
  local s0 = st and st ~= NULL and st:__idx("InternetDeai")
  local can = (s0 == nil or s0 == "Executable") and not StatusManager.Moved.Value
  if T.button("dinder_like", x + 32 + (w - 48) / 2, y + h - 34, (w - 48) / 2, 26, T.st("Dinder_Like", "Like"), { center = true, disabled = busy or not can }) then
    CommandManager:CommandAction_2("InternetDeai")
  end
end

-- KitsuneView.UpdateContents: the thread depends on the story (Yami / Ideon endings, horror days)
-- or on the follower rank; title from Suretai_<rank>, replies from the Kitune master
local function thread_rank()
  local e = EventManager.nowEnding
  if e == "Ending_Yami" then return "Charisma" end
  if e == "Ending_Ideon" then return "Ideon" end
  if EventManager.isHorror then
    local day, part = StatusManager:GetStatus("DayIndex"), StatusManager:GetStatus("DayPart")
    if day == 26 then return part ~= 0 and "Horror_Day2_AfterHaishin" or "Horror_Day2_BeforeHaishin" end
    if day == 27 then return board.forced or "Horror_Day3_third" end
  end
  local f = StatusManager:GetStatus("Follower")
  if f > 1000000 then return "Legend3" elseif f > 750000 then return "Legend2" elseif f > 500000 then return "Legend1"
  elseif f > 400000 then return "Angel3" elseif f > 200000 then return "Angel2" elseif f > 100000 then return "Angel1"
  elseif f > 80000 then return "Shuueki3" elseif f > 40000 then return "Shuueki2" elseif f > 10000 then return "Shuueki1"
  elseif f > 5000 then return "Normal3" elseif f > 2000 then return "Normal2" end
  return "Normal1"
end

local thread_cache = { key = nil }
local function thread(forced)
  local lang = Settings.CurrentLanguage.Value
  local rank = forced or thread_rank()
  local key = rank .. lang .. tostring(EventManager.KituneJien)
  if thread_cache.key == key then return thread_cache end
  local t = { key = key, res = {} }
  local ok, title = pcall(NgoEx.SuretaiFromType, "Suretai_" .. rank:gsub("[123]+$", ""), lang)
  t.title = (ok and title ~= NULL and title) or ""
  local handle = T.st("Kitsune_Handle", "")
  local ok2, list = pcall(NgoEx.KituneFromRank, rank)
  if ok2 and list and list ~= NULL then
    for _, item in EACH(list) do
      local body = NgoEx.KituneFromType(item.Id, lang)
      t.res[#t.res + 1] = { n = item.ResNumber, handle = handle, body = body ~= NULL and body or "" }
    end
  end
  for _, p in ipairs(board.posts) do t.res[#t.res + 1] = { n = 11, handle = handle, body = p } end
  if EventManager.KituneJien and EventManager.KituneJien ~= "" then
    t.res[#t.res + 1] = { n = 11, handle = handle, body = EventManager.KituneJien }
  end
  thread_cache = t
  return t
end

local function draw_thread(x, y, w, h, rank)
  local t = thread(rank)
  G.rect(x, y, w, h, 0xe2e2e2ff)
  local total = 30
  for _, r in ipairs(t.res) do local _, bh = G.measure(r.body, 1, w - 26); r.h = bh + 20; total = total + r.h end
  local sy = T.scroller(scroll, x, y, w, h, total)
  G.clip(x, y, w, h)
  local yy = y + 4 - sy
  local th = G.text(t.title, x + 6, yy, 0xe75252ff, 1, w - 12)
  yy = yy + th + 8
  for _, r in ipairs(t.res) do
    if yy + r.h > y and yy < y + h then
      G.text(r.n .. "：", x + 6, yy, c.ink)
      G.text(r.handle, x + 32, yy, 0x007e82ff, 1, w - 40, 1)
      G.text(r.body, x + 18, yy + 14, c.ink, 1, w - 26)
      if I.tapped(x, math.max(yy, y), w, r.h) then selected = r.body end
    end
    yy = yy + r.h
  end
  G.unclip()
end

-- EgosaView2D.UpdateContents / UpdateHorror: what the ego-search finds
local function egosa_results()
  local lang = Settings.CurrentLanguage.Value
  local r = {}
  local function add(s) if s and s ~= NULL and s ~= "" then r[#r + 1] = s end end
  local hist = EventManager.dayActionHistory
  local last = hist and hist:FindLast(function(st) return STR.Contains(st, "_") end)
  if EventManager.isHorror then
    local hd = StatusManager:GetStatus("DayIndex") - 24
    local part = StatusManager:GetStatus("DayPart")
    if hd == 2 and part == 0 then for i = 0, 9 do add(NgoEx.EgosaString_3(lang, i, "horror", "horrorday2Before")) end
    elseif hd == 2 then for i = 0, 7 do add(NgoEx.EgosaString_3(lang, i, "horror", "horrorday2Afterr")) end
    else
      if last then add(NgoEx.EgosaString_2(lang, "haisin", last)) end
      for i = 0, 1 do add(NgoEx.EgosaString_3(lang, i, "horror", "horrorday1")) end
    end
    return r
  end
  if last then add(NgoEx.EgosaString_2(lang, "haisin", last)) end
  local f = StatusManager:GetStatus("Follower")
  add(NgoEx.EgosaString_2(lang, "follower", f < 10000 and "small" or (f < 100000 and "middle" or "large")))
  for _ = 1, math.max(math.floor(math.log(math.max(1, f), 10)) - 4, 1) do add(NgoEx.EgosaString_2(lang, "random", "random")) end
  return r
end

local function draw_egosa(win, x, y, w, h)
  local st = rawget(win, "egosa")
  if not st then
    st = { t0 = core.now(), res = nil }
    rawset(win, "egosa", st)
    AudioManager:PlaySeByType("SE_yokan")
  end
  -- Sky_Bg_2D tile, the balloon panel, the search box (BaseButtonPressed, pink text)
  G.clip(x, y, w, h)
  for ty = y, y + h, 183 do for tx = x, x + w, 183 do G.draw("result_bg_tile", tx, ty, { w = 183, h = 183 }) end end
  G.unclip()
  G.draw9("balloon", x + 6, y + 4, w - 12, h - 8, 0.5)
  if not G.draw9("BaseButtonPressed", x + 16, y + 10, w - 32, 20, 0.5) then G.rect(x + 16, y + 10, w - 32, 20, c.white) end
  G.text(T.st("Search_egosa", "Egosearch"), x + 24, y + 14, 0xda66d7ff, 1, w - 48, 1)
  local t = core.now() - st.t0
  if t < 0.6 then
    -- the magnifier shaking (120 ms steps)
    local o = ({ { 4, -4 }, { -4, 4 }, { 4, 4 }, { -4, -4 }, { 0, 0 } })[math.floor(t / 0.12) + 1] or { 0, 0 }
    G.draw("icon_desktop_egosearch", x + w / 2 + o[1], y + h / 2 + 10 + o[2], { ax = 0.5, ay = 0.5, fit = { 32, 32 } })
    return
  end
  if not st.res then
    local ok, res = pcall(egosa_results)
    st.res = ok and res or {}
    AudioManager:PlaySeByType("SE_tweet_kusorep")
  end
  local total = 0
  for _, s in ipairs(st.res) do local _, th = G.measure(s, 1, w - 66); total = total + math.max(22, th + 8) + 4 end
  local sy = T.scroller(scroll, x + 10, y + 34, w - 20, h - 42, total)
  G.clip(x + 10, y + 34, w - 20, h - 42)
  local yy = y + 36 - sy
  for _, s in ipairs(st.res) do
    local _, th = G.measure(s, 1, w - 66)
    local hh = math.max(22, th + 8)
    G.rect(x + 14, yy, w - 28, hh, c.white)
    G.draw("icon_kusoripu_black", x + 18, yy + 3, { fit = { 16, 16 } })
    G.text(s, x + 40, yy + 4, 0x1303a6ff, 1, w - 66)
    yy = yy + hh + 4
  end
  G.unclip()
end

function M.draw(win, x0, y0, w0, h0)
  local foro = T.tr({ es = "Foro", en = "Forum", ja = "掲示板" })
  local titles = { Internet = T.st("Window_Internet", "Internet"), Keijiban = foro, KeijibanMini = foro,
                   EgosaResult = T.st("Window_Egosa", "Egosearch"), Dinder = "Dinder" }
  local x, y, w, h = T.window(x0 + 2, y0 + 2, w0 - 4, h0 - 2, titles[win.app] or win.app, "icon_desktop_2ch")
  if win.closeable and T.close("net_close") then
    WindowManager:Close(win) return
  end
  if win.app == "Keijiban" or win.app == "KeijibanMini" then return draw_thread(x, y, w, h) end
  if win.app == "EgosaResult" then return draw_egosa(win, x, y, w, h) end
  if win.app == "Dinder" then return draw_dinder(win, x, y, w, h) end
  G.rect(x, y, w, h, 0xf6f2e8ff)
  local posts = board.posts
  if win.app == "EgosaResult" and EventManager.KituneJien and EventManager.KituneJien ~= "" then posts = { EventManager.KituneJien } end
  local total = 0
  for _, p in ipairs(posts) do local _, ph = G.measure(p, 1, w - 16); total = total + ph + 10 end
  local sy = T.scroller(scroll, x, y, w, h, total)
  G.clip(x, y, w, h)
  local yy = y + 4 - sy
  for i, p in ipairs(posts) do
    local _, ph = G.measure(p, 1, w - 16)
    G.text(i .. ": " .. p, x + 6, yy, c.ink, 1, w - 16)
    if I.tapped(x, yy, w, ph) then selected = p end
    yy = yy + ph + 10
  end
  G.unclip()
end

M.draw_thread = draw_thread

function M.draw_top(win)
  if win and win.app == "Dinder" then
    local cur = dinder_profile()
    G.rect(26, 14, 348, 226, c.white)
    G.draw(dinder.matched and "tinder_match" or cur, 200, 127, { ax = 0.5, ay = 0.5, fit = { 220, 220 } })
    return true
  end
  if not selected then return false end
  G.rect(26, 14, 348, 226, 0xf6f2e8ff)
  G.text(selected, 34, 22, c.ink, 1, 332)
  return true
end

return M
