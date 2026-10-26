-- My Pictures / Image viewer: thumbnails on the bottom, the selected picture full size on top.
local core = require("runtime.core")
local G = require("runtime.gfx")
local I = require("runtime.input")
local T = require("ui.theme")
local c = T.c

local M = { icon = "icon_picture" }
local scroll = {}
local viewer = { current = nil }
-- ImageViewer.SetData(address): the picture to show (ImageViewerHelper.OpenImageViewer)
function viewer:SetData(address) self.current = address end
core.views.ImageViewer = viewer

function M.draw(win, x0, y0, w0, h0)
  local x, y, w, h = T.window(x0 + 2, y0 + 2, w0 - 4, h0 - 2, T.st("Start_Menu_MyPicture", "Mis imágenes"), "icon_picture")
  if win.closeable and T.close("pic_close") then
    WindowManager:Close(win) return
  end
  local imgs = Settings.imageHistory
  local n = imgs and imgs.Count or 0
  local rows = math.ceil(n / 4)
  local sy = T.scroller(scroll, x, y, w, h, rows * 52 + 4)
  G.clip(x, y, w, h)
  for i = 0, n - 1 do
    local id = imgs:__idx(i)
    local bx, by = x + 4 + (i % 4) * 74, y + 4 + math.floor(i / 4) * 52 - sy
    G.rect(bx, by, 70, 48, 0x000000ff)
    G.draw(id, bx + 35, by + 24, { ax = 0.5, ay = 0.5, fit = { 70, 48 } })
    if I.tapped(bx, math.max(by, y), 70, 48) then viewer.current = id end
  end
  G.unclip()
end

function M.draw_top()
  if not viewer.current then return false end
  G.rect(26, 14, 348, 226, 0x000000ff)
  G.draw(viewer.current, 200, 127, { ax = 0.5, ay = 0.5, fit = { 348, 226 } })
  return true
end

return M
