-- NetaChoose: pick the stream topic. Bottom: chip grid (discovered topics + level). Top: preview
-- of the chosen chip (title, description, expected effect). Port of NetachipChooser.cs.
local core = require("runtime.core")
local G = require("runtime.gfx")
local I = require("runtime.input")
local T = require("ui.theme")
local c = T.c

local M = { icon = "icon_desktop_youtube" }
local ALPHAS = { "Zatudan", "Gamejikkyou", "Otakutalk", "Imbouron", "Kaidan", "ASMR", "Hnahaisin", "Kaisetu", "Taiken", "Yamihaishin", "PR", "Angel", "Darkness" }
local chosen = nil
local function lang() return Settings.CurrentLanguage.Value end

local function chip_info(alpha, level)
  local id = alpha .. "_" .. level
  local label = NgoEx.CmdName_2(id, lang())
  if label == NULL or label == "" then label = alpha .. " " .. level end
  local cmd = NgoEx.CmdFromString(id)
  return label, cmd
end

-- NetaChipAlpha texts: genre (CmdName of netaGenre) and the topic title (TenTalk of netaName)
local function chip_texts(alpha, level)
  local d = LoadNetaData.ReadNetaContent(alpha, level)
  if not d or d == NULL then return chip_info(alpha, level), "" end
  local g = NgoEx.CmdName_1(d.netaGenre, lang())
  local n = NgoEx.TenTalk_1(d.netaName, lang())
  return (g ~= NULL and g ~= "" and g) or chip_info(alpha, level), (n ~= NULL and n) or ""
end

-- one chip (netachip_00<level> background, or the gray unknown one with ???)
local function draw_chip(bx, by, cw, ch, it)
  local bg = it.level and it.level > 0 and ("netachip_00" .. math.min(5, it.level)) or "netachip_alpha_unknown"
  if not G.draw(bg, bx, by, { w = cw, h = ch }) then G.rect(bx, by, cw, ch, c.white) end
  if it.level and it.level > 0 then
    local genre, name = chip_texts(it.alpha, it.level)
    G.text(genre, bx + 6, by + 1, 0x1d1a35ff, 1, cw - 14, 1)
    G.text("#" .. name, bx + 6, by + ch - 13, c.ink, 1, cw - 14, 1)
    if it.used then G.rect(bx, by, cw, ch, 0x80808060) end
  else
    G.text_center("???", bx + cw / 2, by + ch / 2 - 6, c.inkSoft)
  end
end

M.draw_chip = draw_chip

function M.back()
  if chosen then chosen = nil return true end
  return false
end

function M.draw(win, x0, y0, w0, h0)
  local x, y, w, h = T.window(x0 + 2, y0 + 2, w0 - 4, h0 - 2, T.st("Window_Neta", "Ideas para el directo"), "icon_desktop_youtube")
  if win.closeable and T.close("neta_close") then
    chosen = nil; WindowManager:Close(win) return
  end
  G.rect(x, y, w, h, 0x161616ff)
  if chosen then
    -- OnStart: the stream icon, the chosen chip, "start" (BaseButton) and "choose again"
    G.draw("icon_desktop_youtube2", x + w / 2, y + 30, { ax = 0.5, ay = 0.5, fit = { 70, 50 } })
    draw_chip(x + w / 2 - 110, y + 60, 220, 30, chosen)
    if T.button("neta_start", x + w / 2 - 75, y + 100, 150, 30, NgoEx.SystemTextFromType("haisin_start_button", lang()), { center = true }) then
      local ch = chosen
      chosen = nil
      EventManager:StartHaishin(ch.alpha, ch.level, "none")
    end
    local back = NgoEx.SystemTextFromType("Reselect", lang())
    local bw = G.measure(back)
    G.text(back, x + w / 2 - bw / 2, y + 140, c.sky)
    if I.tapped(x + w / 2 - 60, y + 136, 120, 18) or I.pressed(I.KEY.B) then chosen = nil end
    return
  end
  -- ChipPage: every topic, discovered ones with their level chip, the rest as ???
  local cols, cw, ch = 2, (w - 12) / 2, 25
  local i = 0
  for _, a in ipairs(ALPHAS) do
    local lv = NetaManager:GetAlphaChipLevel(a) or 0
    if a ~= "Darkness" or lv > 0 then
      i = i + 1
      local used = lv > 0 and NetaManager.usedAlpha:Exists(function(al) return al.alphaType == a and al.level == lv end)
      local it = { alpha = a, level = lv, used = used }
      local bx = x + 4 + ((i - 1) % cols) * (cw + 4)
      local by = y + 4 + math.floor((i - 1) / cols) * (ch + 2)
      draw_chip(bx, by, cw, ch, it)
      local id = "chip" .. a
      if I.focusable(id, bx, by, cw, ch) then T.focus_ring(bx, by, cw, ch) end
      if lv > 0 and (I.tapped(bx, by, cw, ch) or I.activated(id)) then
        if T.click_se then T.click_se() end
        chosen = it
      end
    end
  end
end

-- top: preview card
function M.draw_top(win)
  local it = chosen
  if not it then return false end
  local label, cmd = chip_info(it.alpha, it.level)
  G.rect(26, 14, 348, 226, 0x000000c0)
  G.draw("netaChoose", 200, 127, { ax = 0.5, ay = 0.5, fit = { 348, 226 }, alpha = 0.5 })
  T.panel(40, 40, 320, 150, c.paper)
  G.text(label, 48, 46, c.lilacDark, 1, 300)
  if cmd and cmd ~= NULL then
    local desc = NgoEx.GetCommandDesc(cmd, lang())
    G.text(desc ~= NULL and desc or "", 48, 76, c.ink, 1, 300, 5)
    local y = 160
    local deltas = { { "FollowerDelta", "icon_status_follower" }, { "StressDelta", "icon_status_stress" },
                     { "FavorDelta", "icon_status_love" }, { "YamiDelta", "icon_status_yami" } }
    local x = 48
    for _, d in ipairs(deltas) do
      local v = cmd[d[1]] or 0
      G.draw(d[2], x, y, { fit = { 12, 12 } })
      G.text((v > 0 and "+" or "") .. v, x + 14, y, v > 0 and c.mint or (v < 0 and c.red or c.inkSoft))
      x = x + 76
    end
  end
  return true
end

return M
