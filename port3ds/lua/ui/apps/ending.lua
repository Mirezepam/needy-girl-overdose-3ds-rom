-- App_Ending_Grand / App_Ending_Netshut (App_Poketter2D_Grand / _NetShut): an uncloseable
-- Poketter timeline that scrolls by itself while the ending music plays. Grand runs through
-- Ame's tweets of the whole month; NetShut through the hate replies (kusoreps) she got.
-- Bottom: the scrolling timeline. Top: the tweet passing the middle, its picture full size.
local core = require("runtime.core")
local G = require("runtime.gfx")
local T = require("ui.theme")
local c = T.c
local pk = require("ui.apps.poketter")

local M = {}
local DURATION = { App_Ending_Grand = 106, App_Ending_Netshut = 120 }
local feeds = setmetatable({}, { __mode = "k" })
local centre = nil

local function feed(win)
  local f = feeds[win]
  if f then return f end
  f = { items = {}, total = 0 }
  local hist = PoketterManager.history
  for i = 1, hist and hist.n or 0 do
    local e = pk.entry(hist.items[i])
    if win.app == "App_Ending_Netshut" then
      -- only the replies: one card per kusorep
      for _, r in ipairs(e.replies) do
        local _, h = G.measure(r, 1, pk.W - 40)
        f.items[#f.items + 1] = { text = r, h = h + 10, kuso = true }
      end
    else
      f.items[#f.items + 1] = { e = e, h = e.h }
    end
  end
  for _, it in ipairs(f.items) do f.total = f.total + it.h + 2 end
  feeds[win] = f
  return f
end

function M.draw(win, x0, y0, w0, h0)
  local x, y, w, h = T.window(x0 + 2, y0 + 2, w0 - 4, h0 - 2, "poketter", "icon_taskbar_poketter")
  G.clip(x, y, w, h)
  for ty = y, y + h, 183 do
    for tx = x, x + w, 183 do G.draw("result_bg_tile", tx, ty, { w = 183, h = 183 }) end
  end
  G.unclip()
  if not G.draw9("PoketterNakami2", x + 2, y + 2, w - 4, h - 4, 0.5) then G.rect(x + 2, y + 2, w - 4, h - 4, c.white) end
  local f = feed(win)
  local dur = DURATION[win.app] or 110
  local k = math.min(1, (core.now() - win.opened) / dur)
  local sy = math.max(0, f.total - (h - 8)) * k
  G.clip(x + 2, y + 4, w - 4, h - 8)
  local yy = y + 4 - sy
  centre = nil
  for _, it in ipairs(f.items) do
    if yy + it.h > y and yy < y + h then
      if it.kuso then
        G.rect(x + 4, yy, pk.W, it.h - 2, c.white)
        G.frame_rect(x + 4, yy, pk.W, it.h - 2, 0xd8d0ecff)
        G.draw("icon_kusoripu_black", x + 8, yy + 3, { fit = { 18, 18 } })
        G.text(it.text, x + 32, yy + 4, c.ink, 1, pk.W - 40)
      else
        pk.draw_tweet(it.e, x + 4, yy, false)
      end
      if yy <= y + h / 2 and yy + it.h > y + h / 2 then centre = it end
    end
    yy = yy + it.h + 2
  end
  G.unclip()
end

function M.draw_top()
  G.rect(0, 0, 400, 240, 0x000000ff)
  local e = centre and centre.e
  if e and e.image and G.exists(e.image) then
    G.draw(e.image, 200, 120, { ax = 0.5, ay = 0.5, fit = { 380, 220 } })
  else
    G.draw("bg_stream_grandend", 200, 120, { ax = 0.5, ay = 0.5, fit = { 400, 240 } })
  end
  return true
end

return M
