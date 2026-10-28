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
local draft = ""   -- the FreeForm InputField text
local USER_STAMPS = { "OK", "Saikouka", "Pien", "Waritodoudemoii", "Gomen", "Bujisibou", "Love", "Sorena" }
-- StampTypeToData: the stamp art per language (LoadStampData.ReadStampContent), generated
local STAMP_ART = {
  OK = { JP = "ok_437", EN = "ok_381", SP = "ok_343" },
  Saikouka = { JP = "saikouka_451", EN = "saikouka_385", SP = "saikouka_325" },
  Pien = { JP = "pien_375", EN = "pien_366", SP = "pien_484" },
  Waritodoudemoii = { JP = "waritodoudemoii_444", EN = "waritodoudemoii", SP = "waritodoudemoii_416" },
  Gomen = { JP = "gomen_402", EN = "gomen_392", SP = "gomen_452" },
  Bujisibou = { JP = "bujishibou_389", EN = "bujishibou_456", SP = "bujisyuuryou_438" },
  Love = { JP = "love", EN = "love_398", SP = "love_348" },
  Sorena = { JP = "sorena", EN = "sorena_418", SP = "sorena_498" },
  AmeStamp_ame = { JP = "amechan_421", EN = "amechan_421", SP = "amechan_409" },
  AmeStamp_aseru = { JP = "aseru_415", EN = "aseru_415", SP = "aseru_466" },
  AmeStamp_imajudori = { JP = "imajidorishiteru_488", EN = "imajidorishiteru_353", SP = "imajidorishiteru_412" },
  AmeStamp_kanzennakyuutai = { JP = "kanzennakyuutai_426", EN = "kanzennakyuutai_346", SP = "kanzennakyuutai_344" },
  AmeStamp_kawaikunai = { JP = "kawaikunai", EN = "kawaikunai_434", SP = "kawaikunai_369" },
  AmeStamp_toketeiru = { JP = "toketeiru", EN = "toketeiru", SP = "toketeiru_419" },
  AmeStamp_zzz = { JP = "zzz_430", EN = "zzz_430", SP = "zzz" },
  AmeStamp_kiitenai = { JP = "kiitenai_515", EN = "kiitenai_479", SP = "kiitenai_454" },
}
-- LoadStampData.ReadStampContent(type, CurrentLanguage): each language has its own art
local function stamp_sprite(st)
  local a = STAMP_ART[st]
  return a and (a[Settings.CurrentLanguage.Value] or a.EN) or st
end
local BW = 220   -- bubble wrap width

local function lang() return Settings.CurrentLanguage.Value end

local opened_t, opened_win = 0, nil
local function entry(d)
  local e = cache[d]
  -- texts are resolved in the current language; a language change rebuilds them
  if e and e.lang == Settings.CurrentLanguage.Value then return e end
  local born = e and e.born
  e = { user = d.user }
  if d.user == "separator" then
    e.text = NgoEx.DayText(d.day, lang())
    if e.text == NULL or e.text == "" then e.text = T.st("Day_Live", "DÍA") .. " " .. tostring(d.day) end
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
  -- JineCell2D fades new messages in; the history already there when the window opens does not
  if core.now() - opened_t > 0.4 then e.born = core.now() end
  e.lang, e.born = Settings.CurrentLanguage.Value, e.born or born
  cache[d] = e
  return e
end

local function draw_entry(e, x, y, w)
  if e.user == "separator" or e.user == "timeSeparator" or e.sepLabel then
    -- App_Jine_Separator_2D: date pill (JINE_date) centered
    if (e.text or "") == "" then return end
    -- drawn as a plain pixel pill on whole pixels: the tinted 9-slice smeared the text on hardware
    local tw = math.floor(G.measure(e.text) + 0.5)
    local px, pw = math.floor(x + (w - tw) / 2) - 7, tw + 14
    local py = math.floor(y)
    G.rect(px + 2, py, pw - 4, 13, c.sep)
    G.rect(px + 1, py + 1, pw - 2, 11, c.sep)
    G.rect(px, py + 2, pw, 9, c.sep)
    G.text(e.text, px + 7, py + 1, c.white)
    return
  end
  local ame = e.user ~= "pi"
  if e.stamp then
    local sx = ame and x + 30 or x + w - 62
    if not G.draw(stamp_sprite(e.stamp), sx, y, { fit = { 52, 52 } }) then
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
end

function M.draw(win, x0, y0, w0, h0)
  if opened_win ~= win then opened_win, opened_t = win, core.now() end
  local x, y, w, h = T.window(x0 + 2, y0 + 2, w0 - 4, h0 - 2, T.app_title("Jine", "JINE"), "icon_taskbar_jine")
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
  elseif status == "Stamp" or status == "ChooseAction" then panelH = 58 end
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
  scroll.short = n <= 20
  local sy = T.scroller(scroll, x, y, w, lh, total + 6)
  G.clip(x, y, w, lh)
  local yy = y + 3 - sy
  for _, e in ipairs(entries) do
    if yy + e.h > y and yy < y + lh then
      -- JineCell2D: Fader2D.DOFade 0.4 s (0.2 s for the day separators), DOTween's OutQuad
      local dur = (e.user == "separator" or e.user == "timeSeparator") and 0.2 or 0.4
      local p = e.born and (core.now() - e.born) / dur or 1
      if p < 1 then
        G.push(0, 0, 1, 1 - (1 - p) ^ 2)
        draw_entry(e, x, yy, w - 4)
        G.pop()
      else
        draw_entry(e, x, yy, w - 4)
      end
    end
    yy = yy + e.h
  end
  G.unclip()
  -- "latest" (JINE_button_tobottom, 30x30 at the history's bottom right): shown when a message
  -- arrived while scrolled up; pressing it scrolls down
  if scroll.below then
    local bx, by = math.floor(x + w - 25), math.floor(y + lh - 19)
    G.draw("JINE_button_tobottom", bx, by, { fit = { 15, 15 } })
    if I.focusable("jine_latest", bx - 3, by - 3, 21, 21) then T.focus_ring(bx - 1, by - 1, 17, 17) end
    if I.tapped(bx - 3, by - 3, 21, 21) or I.activated("jine_latest") then T.scroll_to_bottom(scroll) end
  end
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
    -- FreeForm: the TMP InputField (tap types with the system keyboard) and the send Button
    local fx, fw = x + 4, w - 52
    if not G.draw9("InputFieldBackground", fx, py + 3, fw, 24, 0.5) then G.rect(fx, py + 3, fw, 24, c.white) end
    G.text(draft, fx + 6, py + 8, 0x323232ff, 1, fw - 12, 1)
    if I.focusable("jfield", fx, py + 3, fw, 24) then T.focus_ring(fx, py + 3, fw, 24) end
    if I.tapped(fx, py + 3, fw, 24) or I.activated("jfield") then
      core.keyboard("JINE", 60, function(s) if s then draft = s end end)
    end
    if T.button("jfree", x + w - 44, py + 3, 40, 24, "", {}) and draft ~= "" then
      local msg = draft
      draft = ""
      JineManager:EndMessage(msg)
    end
  elseif status == "Stamp" or status == "ChooseAction" then
    -- the Stamp panel is shown as soon as JINE waits for a stamp (JineView2D.showStamp)
    do
      for i, st in ipairs(USER_STAMPS) do
        local col, row = (i - 1) % 4, math.floor((i - 1) / 4)
        local bx, by = x + 4 + col * 76, py + 2 + row * 28
        if T.button("stamp" .. i, bx, by, 72, 26, "", { flat = true }) then send_stamp(st) end
        if not G.draw(stamp_sprite(st), bx + 24, by + 1, { fit = { 24, 24 } }) then G.text(st, bx + 4, by + 8, c.ink, 1, 64, 1) end
      end
    end
  end
end

return M
