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
}
core.views.TinderView = { OnChoosed = function() end }

function M.draw(win, x0, y0, w0, h0)
  local titles = { Internet = "Internet", Keijiban = "Foro", KeijibanMini = "Foro", EgosaResult = "Egosearch", Dinder = "Dinder" }
  local x, y, w, h = T.window(x0 + 2, y0 + 2, w0 - 4, h0 - 2, titles[win.app] or win.app, "icon_desktop_2ch")
  if win.closeable and T.close("net_close") then
    WindowManager:Close(win) return
  end
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

function M.draw_top()
  if not selected then return false end
  G.rect(26, 14, 348, 226, 0xf6f2e8ff)
  G.text(selected, 34, 22, c.ink, 1, 332)
  return true
end

return M
