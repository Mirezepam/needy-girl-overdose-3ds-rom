-- JINE (chat) on the bottom screen: bubbles you drag to scroll, options as big buttons,
-- an 4x2 stamp grid and free text through the system keyboard. Ame stays on the top screen.
local core = require("runtime.core")
local G = require("runtime.gfx")
local I = require("runtime.input")
local T = require("ui.theme")
local c = T.c

local M = { icon = "icon_taskbar_jine" }
local scroll = { stick_bottom = true }
local cache = setmetatable({}, { __mode = "k" })
local stampsOpen = false
local USER_STAMPS = { "OK", "Saikouka", "Pien", "Waritodoudemoii", "Gomen", "Bujisibou", "Love", "Sorena" }
local STAMP_SPRITE = {
  OK = "ok", Saikouka = "saikouka", Pien = "Pien", Waritodoudemoii = "waritodoudemoii", Gomen = "gomen",
  Bujisibou = "bujisibou", Love = "love", Sorena = "sorena", AmeStamp_ame = "ame", AmeStamp_aseru = "aseru",
  AmeStamp_imajudori = "imajidorishiteru", AmeStamp_kanzennakyuutai = "kanzennakyuutai",
  AmeStamp_kawaikunai = "kawaikunai", AmeStamp_kiitenai = "kiitenai", AmeStamp_toketeiru = "toketeiru", AmeStamp_zzz = "zzz",
}
local BW = 220   -- bubble wrap width

local function lang() return Settings.CurrentLanguage.Value end

local function entry(d)
  local e = cache[d]
  if e then return e end
  e = { user = d.user }
  if d.user == "separator" then
    e.text = NgoEx.DayText(d.day, lang())
    if e.text == NULL or e.text == "" then e.text = "Día " .. tostring(d.day) end
  elseif d.user == "timeSeparator" then
    e.text = NgoEx.TimeText(d.day, lang())
    if e.text == NULL then e.text = "" end
  elseif d.responseType == "Stamp" then
    e.stamp = d.stampType
  else
    local dr = JineDataConverter.convertJineDataToDrawable(d)
    e.text = NgoEx.GetJineHonbun(dr, lang())
    if e.text == NULL then e.text = "" end
    local img = dr.ImageId
    e.image = (type(img) == "string" and G.exists(img)) and img or nil
    if d.user == "eventSeparator" then e.sepLabel = true end
    e.user = dr.user or d.user
  end
  local _, h = G.measure(e.text or "", 1, BW)
  if e.stamp then h = 56 elseif e.sepLabel or d.user == "separator" or d.user == "timeSeparator" then h = 14 else h = h + 8 end
  if e.image then h = h + 64 end
  e.h = h + 4
  cache[d] = e
  return e
end

local function draw_entry(e, x, y, w)
  if e.user == "separator" or e.user == "timeSeparator" or e.sepLabel then
    -- App_Jine_Separator_2D: date pill (JINE_date) centered
    if (e.text or "") == "" then return end
    local tw = G.measure(e.text)
    if not G.draw9("JINE_date", x + (w - tw) / 2 - 8, y, tw + 16, 13, 0.5, { tint = 0xab9ed7ff, blend = 1 }) then
      G.rect(x + (w - tw) / 2 - 6, y + 1, tw + 12, 12, c.sep)
    end
    G.text_center(e.text, x + w / 2, y + 1, c.white)
    return
  end
  local ame = e.user ~= "pi"
  if e.stamp then
    local sx = ame and x + 30 or x + w - 62
    if not G.draw(STAMP_SPRITE[e.stamp] or e.stamp, sx, y, { fit = { 52, 52 } }) then
      G.rect(sx, y, 52, 52, c.pink); G.text(e.stamp, sx + 2, y + 20, c.ink, 1, 48)
    end
    if ame then G.draw("icon_jine_ame", x + 1, y, { scale = 0.5 }) end
    return
  end
  if not e.tw then e.tw, e.th = G.measure(e.text, 1, BW) end
  local tw, th = e.tw, e.th
  local bw = math.max(tw, e.image and 80 or 0) + 10
  local bx = ame and x + 31 or x + w - bw - 8
  -- App_Jine_Ame_2D / App_Jine_Pi_2D: avatar, JINE_date balloon (9-slice) and its tail
  if ame then G.draw("icon_jine_ame", x + 1, y, { scale = 0.5 }) end
  local bh = e.h - 4
  if not G.draw9("JINE_date", bx, y, bw, bh, 0.5, ame and nil or { tint = 0xc7ebffff, blend = 1 }) then
    G.rect(bx, y, bw, bh, ame and c.ame or c.pi)
  end
  if ame then G.draw("tail", bx - 4, y + 4, { scale = 0.5 })
  else G.draw("tail", bx + bw + 4, y + 4, { scale = 0.5, sx = -0.5, sy = 0.5, tint = 0xc7ebffff, blend = 1 }) end
  G.text(e.text, bx + 5, y + 4, c.ink, 1, BW)
  if e.image then G.draw(e.image, bx + 5, y + th + 6, { fit = { 80, 60 } }) end
end

local function send_stamp(st)
  local d = NEW("JineData", 5, "pi", "None", "Stamp", st, "")
  spawn(function() JineManager:AddJineHistory_1(d) end)
  stampsOpen = false
end

function M.back()
  if stampsOpen then stampsOpen = false return true end
  return false
end

function M.draw(win, x0, y0, w0, h0)
  local x, y, w, h = T.window(x0 + 2, y0 + 2, w0 - 4, h0 - 2, "JINE", "icon_taskbar_jine")
  if win.closeable and T.close("jine_close") then
    WindowManager:Close(win) return
  end
  -- App_JINE_2D background
  if not G.draw("JINEBG", x, y, { w = w, h = h }) then G.rect(x, y, w, h, 0xfdf6ffff) end
  local status = JineManager.waitStatus and JineManager.waitStatus.Value
  local options = JineManager._options and JineManager._options.list
  local nOpt = options and options.n or 0
  -- bottom panel height depends on what the player can do now
  local panelH = 0
  if nOpt > 0 then panelH = nOpt * 30 + 4
  elseif status == "FreeForm" then panelH = 30
  elseif status == "Stamp" then panelH = stampsOpen and 58 or 22 end
  panelH = math.min(panelH, h - 30)
  local lh = h - panelH
  -- history
  local hist = JineManager.history
  local n = hist and hist.n or 0
  local first = math.max(1, n - 60)   -- only the latest messages are kept on screen (like the original's 25)
  local total = 0
  local entries = {}
  for i = first, n do
    local e = entry(hist.items[i])
    entries[#entries + 1] = e
    total = total + e.h
  end
  local sy = T.scroller(scroll, x, y, w, lh, total + 6)
  G.clip(x, y, w, lh)
  local yy = y + 3 - sy
  for _, e in ipairs(entries) do
    if yy + e.h > y and yy < y + lh then draw_entry(e, x, yy, w - 4) end
    yy = yy + e.h
  end
  G.unclip()
  -- action panel
  local py = y + lh
  if panelH > 0 then T.panel(x, py, w, panelH) end
  if nOpt > 0 then
    for i = 1, nOpt do
      local opt = options.items[i]
      local e = entry(opt)
      if T.button("jopt" .. i, x + 4, py + 3 + (i - 1) * 30, w - 8, 27, e.text, { fill = c.pi, maxLines = 2 }) then
        spawn(function() JineManager:AddJineHistory_1(opt) end)
        JineManager:EndOption()
        scroll.y = 1e9
        break
      end
    end
  elseif status == "FreeForm" then
    if T.button("jfree", x + 4, py + 3, w - 8, 24, "✎ Escribir…", { fill = c.pi }) then
      local s = sys.keyboard("JINE", "", 60)
      if s and s ~= "" then JineManager:EndMessage(s) end
    end
  elseif status == "Stamp" then
    if stampsOpen then
      for i, st in ipairs(USER_STAMPS) do
        local col, row = (i - 1) % 4, math.floor((i - 1) / 4)
        local bx, by = x + 4 + col * 76, py + 2 + row * 28
        if T.button("stamp" .. i, bx, by, 72, 26, "", { flat = true }) then send_stamp(st) end
        if not G.draw(STAMP_SPRITE[st], bx + 24, by + 1, { fit = { 24, 24 } }) then G.text(st, bx + 4, by + 8, c.ink, 1, 64, 1) end
      end
    elseif T.button("jstamps", x + 4, py + 2, w - 8, 18, "☺ Stickers", { center = true, flat = true }) then
      stampsOpen = true
    end
  end
end

return M
