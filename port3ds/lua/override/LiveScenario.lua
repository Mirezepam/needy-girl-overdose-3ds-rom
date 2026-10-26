-- LiveScenario (transpiled) bound to the 3DS Live view: the original found its Live component
-- through the Unity hierarchy, which does not exist here.
local core = require("runtime.core")
local C = require("gen.LiveScenario")

local awake = C.Awake
function C:Awake()
  awake(self)
  self._Live = core.views.Live
end

-- a broadcast replaced by a new one (the stream window reopened) is cancelled like the original's
-- token: its loop stops and nothing after it (HaishinClean, after-stream events) runs
local play = C.PlayScenario
function C:PlayScenario()
  if not coroutine.isyieldable() then spawn(C.PlayScenario, self) return end
  local live = self._Live
  local orig_play = self.Play
  self.Play = function(sc, ctx)
    if rawget(sc, "_aborted") or (live and core.views.Live ~= live) then
      rawset(sc, "_aborted", true)
      error({ canceled = true }, 0)
    end
    return orig_play(sc, ctx)
  end
  play(self)
  if rawget(self, "_aborted") or (live and core.views.Live ~= live) then error({ canceled = true }, 0) end
end

return C
