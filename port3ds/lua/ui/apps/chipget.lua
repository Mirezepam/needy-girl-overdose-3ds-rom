-- ChipGetCover: the "new stream idea" cover (ChipGet_Show event). Fades in a window titled
-- neta_get with System_NetaGet and the new chip, plays SE_Tetehen; OK (or A) ends it and the
-- event continues when isGetting turns false.
local core = require("runtime.core")
local G = require("runtime.gfx")
local I = require("runtime.input")
local T = require("ui.theme")
local c = T.c

local M = {}
local cover = { isGetting = core.RP.new(false), shown = nil, t0 = 0, closing = nil }

function cover:getNewChip(type, level)
  self.shown = { alpha = type, level = level }
  self.t0, self.closing = core.now(), nil
  self.isGetting.Value = true
  spawn(function()
    core.wait_ms(400)
    AudioManager:PlaySeByType("SE_Tetehen")
  end)
end

function cover:EndGet()
  if not self.shown or self.closing then return end
  self.closing = core.now()
  spawn(function()
    core.wait_ms(200)
    self.shown, self.closing = nil, nil
    self.isGetting.Value = false
    TooltipManager:Hide()
  end)
end
cover.NectButton = NULL
M.cover = cover

function M.active() return cover.shown ~= nil end

function M.draw()
  local s = cover.shown
  if not s then return end
  local a = cover.closing and math.max(0, 1 - (core.now() - cover.closing) / 0.2) or math.min(1, (core.now() - cover.t0) / 0.4)
  G.rect(0, 0, 320, 240, math.floor(a * 0x90))
  if a < 0.3 then return end
  local x, y, w, h = T.window(30, 46, 260, 140, T.st("neta_get", "!"), "icon_desktop_youtube")
  G.rect(x, y, w, h, 0x161616ff)
  G.text_center(T.st("System_NetaGet", ""), x + w / 2, y + 8, c.white, 1, w - 12)
  -- the chip grows in (DOScale 0.3 s after the fade)
  local k = math.min(1, math.max(0.2, (core.now() - cover.t0 - 0.4) / 0.3))
  local cw, ch = 220 * k, 30 * k
  require("ui.apps.neta").draw_chip(x + w / 2 - cw / 2, y + 40 + (30 - ch) / 2, cw, ch,
    { alpha = s.alpha, level = s.level })
  if T.button("chipget_ok", x + w / 2 - 50, y + h - 34, 100, 26, T.st("Dialog_OK", "OK"), { center = true })
    or I.pressed(I.KEY.A) then
    cover:EndGet()
  end
end

return M
