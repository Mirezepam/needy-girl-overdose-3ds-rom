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

-- startEvent without the cancellation check. The original cancels its event token on every
-- time-passing notice (NotificationManager -> ClearEventQueue) and never makes a new one; the 363
-- events that call base.startEvent without awaiting it ignore that, but the three that await it
-- (Event_Fetish, Event_Haikuwoyome, Event_Test) were cancelled on the spot and left the game
-- "eventing" until the next action. The queue itself is still cleared by ClearEventQueue.
function C:startEvent(cancellationToken, skipWatchSp)
  if not coroutine.isyieldable() then spawn(C.startEvent, self, cancellationToken, skipWatchSp) return end
  if not self.isStarted then
    JineManager:Uncontrolable()
    if not skipWatchSp then WebCamManager:WatchSp() end
    self.isStarted = true
  end
end

return C
