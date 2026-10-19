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

function M.back()
  if chosen then chosen = nil return true end
  return false
end

function M.draw(win, x0, y0, w0, h0)
  local x, y, w, h = T.window(x0 + 2, y0 + 2, w0 - 4, h0 - 2, "Elegir tema del directo", "icon_desktop_youtube")
  if win.closeable and T.close("neta_close") then
    chosen = nil; WindowManager:Close(win) return
  end
  if chosen then
    local label = chip_info(chosen.alpha, chosen.level)
    G.text(label, x + 6, y + 6, c.ink, 1, w - 12)
    G.text("Nivel " .. chosen.level .. (chosen.used and "  (ya emitido)" or ""), x + 6, y + 40, c.inkSoft)
    if T.button("neta_start", x + 30, y + 80, w - 60, 40, NgoEx.SystemTextFromType("haisin_start_button", lang()), { center = true, fill = c.pink }) then
      local ch = chosen
      chosen = nil
      EventManager:StartHaishin(ch.alpha, ch.level, "none")
    end
    if T.button("neta_back", x + 30, y + 130, w - 60, 26, NgoEx.SystemTextFromType("Reselect", lang()), { center = true }) then chosen = nil end
    return
  end
  local list = {}
  for _, a in ipairs(ALPHAS) do
    local lv = NetaManager:GetAlphaChipLevel(a)
    if lv and lv > 0 then
      local used = NetaManager.usedAlpha:Exists(function(al) return al.alphaType == a and al.level == lv end)
      list[#list + 1] = { alpha = a, level = lv, used = used }
    end
  end
  if #list == 0 then G.text("No tienes temas todavía.", x + 6, y + 6, c.inkSoft) end
  for i, it in ipairs(list) do
    local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
    local bx, by = x + 4 + col * ((w - 12) / 2 + 4), y + 4 + row * 34
    local label = chip_info(it.alpha, it.level)
    if T.button("chip" .. it.alpha, bx, by, (w - 12) / 2, 30, label, { fill = it.used and 0xe6e0f0ff or c.white, maxLines = 2 }) then
      chosen = it
    end
    if I.long_pressed(bx, by, (w - 12) / 2, 30) then chosen = it end
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
