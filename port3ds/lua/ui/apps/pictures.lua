-- My Pictures (MyPictureController_Sprit): the folder view first, scenario folders of 11 pictures
-- each ("PictureFolder", "PictureFolder 1"...) and the 30 zip folders (locked until a ChooseZip
-- opened them); a folder shows its MyPictureContentView cells (Id title, the picture or
-- NoImagePicture when not seen yet) and the return button goes back. A cell opens the picture,
-- shown full size on the top screen (ImageViewer).
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

local PER_FOLDER, ZIPS = 11, 30
local view = { win = nil, folder = nil }

local cached
local function lists()
  if cached then return cached[1], cached[2] end
  local scen, fan = {}, {}
  for _, r in EACH(ImageViewerHelper.LoadResourcesList() or List.new()) do
    if r.Id:sub(1, 1) == "@" then fan[#fan + 1] = r else scen[#scen + 1] = r end
  end
  cached = { scen, fan }
  return scen, fan
end

local function folder_label(i)
  local s = T.st("PictureFolder", "PictureFolder")
  return i == 1 and s or (s .. " " .. (i - 1))
end

local function draw_folders(x, y, w, h, scen)
  local folders = {}
  for i = 1, math.ceil(#scen / PER_FOLDER) do folders[#folders + 1] = { scen = i, label = folder_label(i) } end
  for i = 1, ZIPS do folders[#folders + 1] = { zip = i, label = tostring(i), locked = not Settings.unLockedZip:Contains(i) } end
  local cols, cw, ch = 4, (w - 8) / 4, 50
  local sy = T.scroller(scroll, x, y, w, h, math.ceil(#folders / cols) * ch + 4)
  G.clip(x, y, w, h)
  for i, f in ipairs(folders) do
    local bx, by = x + 4 + ((i - 1) % cols) * cw, y + 4 + math.floor((i - 1) / cols) * ch - sy
    if by > y - ch and by < y + h then
      G.draw(f.locked and "icon_desktop_folder_zip" or "icon_desktop_folder_open1", bx + cw / 2 - 14, by + 2, { fit = { 28, 28 } })
      G.text_center(f.label, bx + cw / 2, by + 32, f.locked and c.inkSoft or c.ink, 1, cw - 4)
      local id = "pf" .. i
      if I.focusable(id, bx, by, cw, ch - 2) then T.focus_ring(bx, by, cw, ch - 2); T.reveal(scroll, by, ch - 2, y, h) end
      if not f.locked and (I.tapped(bx, math.max(by, y), cw, ch - 2) or I.activated(id)) then
        AudioManager:PlaySeByType("SE_piporo")
        view.folder, scroll.y = f, 0
      end
    end
  end
  G.unclip()
end

local function draw_pictures(x, y, w, h, scen, fan)
  local f = view.folder
  local cells = {}
  local seen = {}
  for _, p in EACH(Settings.imageHistory) do seen[tostring(p)] = true end
  if f.scen then
    for k = (f.scen - 1) * PER_FOLDER + 1, math.min(f.scen * PER_FOLDER, #scen) do
      local r = scen[k]
      cells[#cells + 1] = { title = r.Id, file = seen[r.FileName] and r.FileName or "NoImagePicture" }
    end
  else
    for k = f.zip, #fan, ZIPS do cells[#cells + 1] = { title = fan[k].Id, file = fan[k].FileName } end
  end
  -- openFolderText + returnButton
  G.text(f.label, x + 30, y + 3, c.ink, 1, w - 40, 1)
  if T.button("pic_back", x + 4, y + 2, 22, 14, "◀", { center = true, flat = true }) then
    view.folder, scroll.y = nil, 0
    return
  end
  local top = 18
  local cols, cw, ch = 4, (w - 8) / 4, 60
  local sy = T.scroller(scroll, x, y + top, w, h - top, math.ceil(#cells / cols) * ch + 4)
  G.clip(x, y + top, w, h - top)
  for i, cell in ipairs(cells) do
    local bx, by = x + 4 + ((i - 1) % cols) * cw, y + top + 2 + math.floor((i - 1) / cols) * ch - sy
    if by > y - ch and by < y + h then
      G.rect(bx + 2, by, cw - 4, 44, 0x000000ff)
      if not G.draw(cell.file, bx + cw / 2, by + 22, { ax = 0.5, ay = 0.5, fit = { cw - 4, 44 } }) then
        G.text_center("?", bx + cw / 2, by + 16, c.inkSoft)
      end
      G.text_center(cell.title, bx + cw / 2, by + 46, c.ink, 1, cw - 4)
      local id = "pic" .. i
      if I.focusable(id, bx, by, cw, ch - 2) then T.focus_ring(bx + 2, by, cw - 4, 44); T.reveal(scroll, by, ch - 2, y + top, h - top) end
      if cell.file ~= "NoImagePicture" and (I.tapped(bx, math.max(by, y + top), cw, ch - 2) or I.activated(id)) then
        viewer.current = cell.file
      end
    end
  end
  G.unclip()
end

function M.back()
  if view.folder then view.folder, scroll.y = nil, 0 return true end
  return false
end

function M.draw(win, x0, y0, w0, h0)
  if view.win ~= win then view.win, view.folder, viewer.current, scroll.y = win, nil, nil, 0 end
  local x, y, w, h = T.window(x0 + 2, y0 + 2, w0 - 4, h0 - 2, T.app_title("MyPicture"), "icon_picture")
  if win.closeable and T.close("pic_close") then
    WindowManager:Close(win) return
  end
  G.rect(x, y, w, h, c.white)
  local scen, fan = lists()
  if view.folder then draw_pictures(x, y, w, h, scen, fan) else draw_folders(x, y, w, h, scen) end
end

function M.draw_top()
  if not viewer.current then return false end
  G.rect(26, 14, 348, 226, 0x000000ff)
  G.draw(viewer.current, 200, 127, { ax = 0.5, ay = 0.5, fit = { 348, 226 } })
  return true
end

return M
