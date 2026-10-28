-- Head-pat minigame (NgoEvent.NadeNade). On PC you hovered the mouse over Ame's head on the
-- webcam; on 3DS the webcam is on the top screen, so the bottom screen shows a close-up of her
-- head and each stylus stroke counts as one pat (Amehead.NadeCount).
local core = require("runtime.core")
local G = require("runtime.gfx")
local I = require("runtime.input")
local T = require("ui.theme")
local c = T.c

local M = {}
local amehead = { NadeCount = core.RP.new(0) }
local stroke = { dist = 0, lastx = nil }

-- views the game code reaches through WindowManager:GetNakamiFromApp("Webcam")
-- (the rest of App_Webcam lives in ui/top.lua)
local wc = core.views.App_Webcam or {}
core.views.App_Webcam = wc
wc.AmeHead = { GetComponent = function() return amehead end }

-- the event makes the webcam window uncloseable while it waits for pats
function M.active()
  local w = WindowManager:find("Webcam")
  return w ~= nil and w.closeable == false
end

function M.draw()
  G.rect(0, 0, 320, 220, 0xfff0f8ff)
  -- close-up: the current webcam frame zoomed on Ame's head
  local cam = WebCamManager
  G.clip(0, 0, 320, 220)
  local cur = core.views.App_Webcam.CurrentAnim or "stream_ame_idle"
  if not G.play(cur, core.now() % 4, -190, -60, { scale = 2.4 }) then
    G.play("stream_ame_idle", core.now(), -190, -60, { scale = 2.4 })
  end
  G.unclip()
  local n = amehead.NadeCount.Value
  for i = 0, 2 do
    G.draw("icon_heart", 128 + i * 24, 172, { fit = { 16, 16 }, alpha = (n % 3) > i and 1 or 0.3 })
  end
  -- a stroke = 60 px of stylus travel across the head
  if I.touching and I.ty < 190 then
    if stroke.lastx then
      stroke.dist = stroke.dist + math.abs(I.tx - stroke.lastx) + math.abs(I.drag_dy)
    end
    stroke.lastx = I.tx
    if stroke.dist > 60 then
      stroke.dist = 0
      amehead.NadeCount.Value = amehead.NadeCount.Value + 1
      AudioManager:PlaySeByType("SE_nadenade_1")
    end
  else
    stroke.lastx = nil
  end
  -- buttons fallback: A pats too
  if I.pressed(I.KEY.A) then
    amehead.NadeCount.Value = amehead.NadeCount.Value + 1
    AudioManager:PlaySeByType("SE_nadenade_1")
  end
end

M.amehead = amehead
return M
