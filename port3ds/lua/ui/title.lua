-- Title / boot: BIOS + Windose logo on the top screen; save slots and language on the bottom.
local core = require("runtime.core")
local G = require("runtime.gfx")
local I = require("runtime.input")
local T = require("ui.theme")
local boot = require("runtime.boot")
local K = I.KEY

local M = {}
local ui
local t = 0
local lang = "es"
local slots = {}
local LANGS = { { "es", "Español" }, { "en", "English" }, { "ja", "日本語" } }
local L = {
  es = { title = "Elige partida", new = "Nueva partida", cont = "Continuar (día %d)", lang = "Idioma",
         hint = "Toca una ranura o usa la cruceta + A", slot = "Ranura %d" },
  en = { title = "Choose a save", new = "New game", cont = "Continue (day %d)", lang = "Language",
         hint = "Tap a slot or use the D-pad + A", slot = "Slot %d" },
  ja = { title = "セーブをえらぶ", new = "はじめから", cont = "つづきから（%d日目）", lang = "げんご",
         hint = "タップかＡボタン", slot = "スロット%d" },
}

local function scan()
  for i = 1, 3 do
    local f, day = boot.latest_save(i)
    slots[i] = { file = f, day = day }
  end
end

function M.init(u)
  ui = u
  scan()
  local s = sys.read("sdmc:/3ds/needy3ds/save/port_lang.txt")
  if s and (s == "es" or s == "en" or s == "ja") then lang = s end
  sys.bgm_play(sys.data .. "snd/BIOS_HDD.ogg", false)
end

function M.update(dt) t = t + dt end

local function start(slot, cont)
  sys.mkdir("sdmc:/3ds/needy3ds/save")
  sys.write("sdmc:/3ds/needy3ds/save/port_lang.txt", lang)
  sys.bgm_stop()
  ui.start_game({ lang = lang, slot = slot, saveFile = cont and slots[slot].file or nil })
end

function M.draw(screen)
  local s = L[lang]
  if screen == 0 then
    if t < 2.2 then
      G.rect(0, 0, 400, 240, 0x000000ff)
      if not G.draw("boot_bios", 200, 120, { ax = 0.5, ay = 0.5, fit = { 400, 240 } }) then
        G.text("Windose BIOS ... OK", 10, 10, 0xc0c0c0ff)
      end
    else
      G.rect(0, 0, 400, 240, 0xfff0faff)
      G.draw("boot_logo", 200, 100, { ax = 0.5, ay = 0.5, fit = { 360, 160 } })
      G.text_center("NEEDY GIRL OVERDOSE  3DS", 200, 200, T.c.lilacDark)
      G.text_center("fan port", 200, 214, T.c.inkSoft)
    end
    return
  end
  G.rect(0, 0, 320, 240, T.c.desk)
  G.draw("FHDbg", 160, 120, { ax = 0.5, ay = 0.5, fit = { 320, 240 }, alpha = 0.6 })
  local x, y, w, h = T.window(8, 6, 304, 196, s.title, "icon_desktop_folder_open1")
  for i = 1, 3 do
    local sl = slots[i]
    local by = y + 4 + (i - 1) * 46
    G.text(string.format(s.slot, i), x + 6, by + 2, T.c.inkSoft)
    if sl.file then
      if T.button("cont" .. i, x + 4, by + 14, 170, 26, string.format(s.cont, sl.day), { fill = T.c.mint }) then start(i, true) end
      if T.button("new" .. i, x + 180, by + 14, 112, 26, s.new) then start(i, false) end
    else
      if T.button("new" .. i, x + 4, by + 14, 288, 26, s.new, { fill = T.c.pi }) then start(i, false) end
    end
  end
  -- language selector
  G.text(s.lang, 12, 210, T.c.white)
  for i, l in ipairs(LANGS) do
    local bx = 80 + (i - 1) * 78
    if T.button("lang" .. l[1], bx, 206, 72, 24, l[2], { center = true, fill = lang == l[1] and T.c.pink or T.c.white }) then
      lang = l[1]
    end
  end
end

return M
