-- NgoEvent (transpiled) with DelaySkippable rewritten: the original awaited WhenAny(delay, click);
-- here the coroutine waits for the delay, a tap on either screen, or the A button.
local core = require("runtime.core")
local C = require("gen.NgoEvent")

function C.DelaySkippable(ms)
  if core.fast then core.wait_frames(1) return end
  local t = core.now() + (ms or 0) / 1000
  local I = core.input
  core.wait_until(function()
    return core.fast or core.now() >= t or I.tap_down or I.pressed(I.KEY.A)
  end)
end

return C
