-- Ending_Ideon site windows (Ideon_2ch / hutaba / nico / news / Insta / wiki / taiki), popping all
-- at once over the desktop. Their content comes from the original prefabs (data/ideon.lua, made
-- by tools/export_ideon.py): texts in the chosen language when the game has them, images.
-- Bottom: the windows cascaded, the front one readable and scrollable; tap one to bring it up.
-- Top: Ideon_taiki, the waiting room of the stream with its comments scrolling.
local core = require("runtime.core")
local G = require("runtime.gfx")
local I = require("runtime.input")
local T = require("ui.theme")
local data = require("runtime.data")
local c = T.c

local M = {}
local pages = nil
local front = nil
local scroll = {}
local TITLES = { Ideon_2ch = "2ch", Ideon_hutaba = "futaba", Ideon_nico = "niconico", Ideon_news = "news",
                 Ideon_Insta = "insta", Ideon_wiki = "wiki", Ideon_taiki = "live" }
local ORDER = { "Ideon_taiki", "Ideon_2ch", "Ideon_hutaba", "Ideon_nico", "Ideon_news", "Ideon_Insta", "Ideon_wiki" }

local function load()
  if pages then return pages end
  local ok, t = pcall(dofile, sys.data .. "data/ideon.lua")
  pages = ok and t or {}
  return pages
end

-- text of an item: the translation when there is one, the Japanese placeholder only in Japanese
-- or when it has no Japanese in it (numbers, handles, "Kawaii!!!!")
local function item_text(it)
  if it.id then
    local s = data.any_text(it.id)
    if s and s ~= "" then return s end
  end
  local t = it.t
  if not t then return nil end
  if Settings.CurrentLanguage.Value == "JP" or not t:find("[\227-\233]") then return t end
  return nil
end

local function page_height(items, w)
  local h = 4
  for _, it in ipairs(items) do
    if it.img then h = h + 64
    else
      local s = item_text(it)
      if s then local _, th = G.measure(s, 1, w); h = h + th + 4 end
    end
  end
  return h
end

local function draw_page(app, x, y, w, h, interactive)
  -- the 2ch window is the forum with the Ideon thread (KitsuneView, nowEnding Ideon)
  if app == "Ideon_2ch" and interactive then
    return require("ui.bottom").app_module("internet").draw_thread(x, y, w, h, "Ideon")
  end
  local items = load()[app] or {}
  G.rect(x, y, w, h, app == "Ideon_2ch" and 0xe2e2e2ff or c.white)
  local st = scroll[app] or {}
  scroll[app] = st
  local sy = interactive and T.scroller(st, x, y, w, h, page_height(items, w - 12)) or 0
  G.clip(x, y, w, h)
  local yy = y + 4 - sy
  for _, it in ipairs(items) do
    if it.img then
      G.draw(it.img, x + w / 2, yy + 30, { ax = 0.5, ay = 0.5, fit = { w - 20, 60 } })
      yy = yy + 64
    else
      local s = item_text(it)
      if s then
        local th = G.text(s, x + 6, yy, it.c or c.ink, 1, w - 12)
        yy = yy + th + 4
      end
    end
    if yy > y + h + 20 then break end
  end
  G.unclip()
end

local function open_sites()
  local list = {}
  for _, app in ipairs(ORDER) do
    local w = WindowManager:find(app)
    if w and w.kind == "ideon" then list[#list + 1] = w end
  end
  return list
end

function M.draw(win, x0, y0, w0, h0)
  local list = open_sites()
  if not front or not WindowManager:find(front) then front = win.app end
  -- cascade: back windows first, the front one last and bigger
  local n = #list
  for i, w in ipairs(list) do
    if w.app ~= front then
      local bx, by = 4 + (i - 1) * 16, 4 + (i - 1) * 12
      local x, y, ww, hh = T.window(bx, by, 200, 110, T.app_title(w.app, TITLES[w.app]), "icon_desktop_internet")
      draw_page(w.app, x, y, ww, hh, false)
      if I.tapped(bx, by, 200, 110) then front = w.app; AudioManager:PlaySeByType("SE_click") end
    end
  end
  local x, y, w, h = T.window(70, 40, 246, h0 - 44, T.app_title(front, TITLES[front]), "icon_desktop_internet")
  draw_page(front, x, y, w, h, true)
  -- App_taiki's "start" button (ActionIdeon): always interactable, starts the last stream
  -- (ThrottleFirst 2 s like the original)
  if WindowManager:find("Ideon_taiki") then
    local label = T.st("Shortcut_Haishin", "Live")
    if T.button("ideon_start", 4, h0 - 32, 62, 26, label, { center = true }) and core.now() - (M.started or -10) > 2 then
      M.started = core.now()
      EventManager:AddEvent_1("HaishinStart_Ideon")
    end
  end
  if n > 1 and I.pressed(I.KEY.R) then
    for i, wn in ipairs(list) do
      if wn.app == front then front = list[i % n + 1].app break end
    end
  end
end

-- top: the stream waiting room (App_taiki): gold-shield room tinted night blue, the waiting count
-- and the comments scrolling up
function M.draw_top()
  if not WindowManager:find("Ideon_taiki") then return false end
  G.rect(0, 0, 400, 240, c.paper2)
  G.rect(0, 0, 400, 13, c.white)
  G.text("▶", 4, 1, c.red); G.text("live", 14, 1, c.red)
  G.text("100.000.000 " .. T.st("Haisin_Watching_Number", ""), 44, 1, c.inkSoft, 1, 340, 1)
  G.draw("bg_stream_shield_gold", 26, 14, { w = 348, h = 226, tint = 0x233c84ff, blend = 0.55 })
  local items = load().Ideon_taiki or {}
  local lines = {}
  for _, it in ipairs(items) do
    local s = not it.img and item_text(it)
    if s and it.c ~= 0x888888ff then lines[#lines + 1] = s end
  end
  if #lines > 0 then
    local t = core.now() * 0.8
    for k = 0, 8 do
      local s = lines[(math.floor(t) + k) % #lines + 1]
      local yy = 220 - k * 22 - (t % 1) * 22
      G.rect(240, yy, 130, 18, 0xffffffd0)
      G.draw("CommentIcon", 244, yy + 5, { fit = { 8, 8 } })
      G.text(s, 256, yy + 3, c.ink, 1, 112, 1)
    end
  end
  return true
end

return M
