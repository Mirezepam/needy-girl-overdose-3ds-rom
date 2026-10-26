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
         hint = "Toca una ranura o usa la cruceta + A", slot = "Ranura %d", day = "DÍA %d",
         nosnd = "Sin sonido: falta sdmc:/3ds/dspfirm.cdc (usa DSP1)" },
  en = { title = "Choose a save", new = "New game", cont = "Continue (day %d)", lang = "Language",
         hint = "Tap a slot or use the D-pad + A", slot = "Slot %d", day = "DAY %d",
         nosnd = "No sound: sdmc:/3ds/dspfirm.cdc missing (run DSP1)" },
  ja = { title = "セーブをえらぶ", new = "はじめから", cont = "つづきから（%d日目）", lang = "げんご",
         hint = "タップかＡボタン", slot = "スロット%d", day = "%d日目",
         nosnd = "音が出ません：sdmc:/3ds/dspfirm.cdc がない（DSP1）" },
}

local function scan()
  for i = 1, 3 do
    local f, day = boot.latest_save(i)
    slots[i] = { file = f, day = day, days = boot.saves(i), scroll = {} }
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

local function start(slot, cont, file)
  sys.mkdir("sdmc:/3ds/needy3ds/save")
  sys.write("sdmc:/3ds/needy3ds/save/port_lang.txt", lang)
  sys.bgm_stop()
  ui.start_game({ lang = lang, slot = slot, saveFile = file or (cont and slots[slot].file) or nil })
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
      -- ndsp needs the console's DSP firmware dump; without it the whole game is silent
      if sys.audio_ok and not sys.audio_ok() then
        G.rect(0, 228, 400, 12, 0x000000a0)
        G.text_center(s.nosnd, 200, 229, 0xffffffff)
      end
    end
    return
  end
  G.rect(0, 0, 320, 240, T.c.desk)
  G.draw("FHDbg", 160, 120, { ax = 0.5, ay = 0.5, fit = { 320, 240 }, alpha = 0.6 })
  -- App_Load: white window, sky-blue header, one DataComponent per slot ("DataN", gray and ink
  -- rules, the action button, and the row of saved days to load any of them)
  local x, y, w, h = T.window(8, 6, 304, 196, s.title, "icon_desktop_folder_open1")
  G.rect(x, y, w, h, T.c.white)
  G.rect(x, y, w, 10, T.c.sky)
  for i = 1, 3 do
    local sl = slots[i]
    local by = y + 13 + (i - 1) * 55
    G.text("Data" .. i, x + 8, by, T.c.ink, 1.5)
    G.rect(x + 4, by + 19, w - 8, 1, 0x878787ff)
    G.rect(x + 4, by + 20, w - 8, 1, T.c.ink)
    local label = sl.file and string.format(s.cont, sl.day) or s.new
    if T.button("load" .. i, x + w - 132, by, 128, 18, label, { center = true }) then start(i, sl.file ~= nil) end
    -- saved days of this slot (scroll with the stylus); "+" starts over in this slot
    local rx, ry, rw = x + 4, by + 24, w - 8
    local cw = 46
    local neww = G.measure("+ " .. s.new) + 16
    local total = #sl.days * (cw + 3) + (sl.file and neww or 0)
    sl.scroll.x = math.max(0, math.min(math.max(0, total - rw), (sl.scroll.x or 0) - (I.touching_in(rx, ry, rw, 26) and I.drag_dx or 0)))
    G.clip(rx, ry, rw, 26)
    for k, d in ipairs(sl.days) do
      -- D-pad focus on a chip outside the row scrolls it into view
      if I.focus_visible and I.focus_id == "day" .. i .. "_" .. d.day then
        local left = (k - 1) * (cw + 3)
        if left < sl.scroll.x then sl.scroll.x = left
        elseif left + cw > sl.scroll.x + rw then sl.scroll.x = left + cw - rw end
      end
      local cx = rx + (k - 1) * (cw + 3) - sl.scroll.x
      if T.button("day" .. i .. "_" .. d.day, cx, ry + 2, cw, 22, string.format(s.day, d.day), { center = true, flat = true, fill = T.c.pi }) then
        start(i, true, d.file)
      end
    end
    if sl.file then
      if I.focus_visible and I.focus_id == "new" .. i then sl.scroll.x = math.max(0, total - rw) end
      local cx = rx + #sl.days * (cw + 3) - sl.scroll.x
      if T.button("new" .. i, cx, ry + 2, neww, 22, "+ " .. s.new, { center = true, flat = true }) then start(i, false) end
    end
    G.unclip()
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
