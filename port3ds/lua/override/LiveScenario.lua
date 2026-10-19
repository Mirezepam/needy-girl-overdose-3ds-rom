-- LiveScenario (transpiled) bound to the 3DS Live view: the original found its Live component
-- through the Unity hierarchy, which does not exist here.
local core = require("runtime.core")
local C = require("gen.LiveScenario")

local awake = C.Awake
function C:Awake()
  awake(self)
  self._Live = core.views.Live
end

return C
