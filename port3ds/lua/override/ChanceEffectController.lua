-- ChanceEffectController: the pachinko-style "chance" effects (chainsaw, danger, angel...) the
-- endings and streams trigger. On PC they are animated columns at both sides of the screen
-- (ChanceEffectCanvas LeftGroup / RightGroup, 240 px of 1920); here they are drawn at both sides
-- of the top screen by ui/top.lua, playing the clip of the controller's current state.
local core = require("runtime.core")
local C = class("ChanceEffectController", "SingletonMonoBehaviour")

C._ANIM_DEFAULT = "default"
C._ANIM_IN = "in"
C._ANIM_WIN_STOP = "win_stop"
C._ANIM_WIN = "win"
C._ANIM_OUT = "out"

function C:__fields()
  self.effect = nil    -- "Chainsaw", "Danger", ...
  self.state = nil     -- animator state
  self.t0 = 0
  -- streams drive the effect through these (LiveScenario.Play: _current = obi, _anim = inout)
  local me = self
  self._current = core.RP.new(nil)
  self._anim = core.RP.new(nil)
  self._current:Subscribe(function(v) if v and v ~= NULL and v ~= "None" then me.effect = v end end)
  self._anim:Subscribe(function(v) if v and v ~= NULL and v ~= "" then me:play(v) end end)
end

C.__getters.ChanceEffects = function() return core.List.new() end

function C:Start() end

function C:play(state)
  self.state, self.t0 = state, core.now()
end

function C:OnReach(type)
  self.effect = type
  self:play(C._ANIM_IN)
end
function C:OnFever() self:play(C._ANIM_WIN) end
function C:OnFeverStart() self:play(C._ANIM_WIN_STOP) end
function C:OnOut() self:play(C._ANIM_OUT) end

-- current sprite clip for the top screen: follows exit-time transitions (in -> idle), the out
-- state ends the effect
function C:current_clip(G)
  if not self.effect then return nil end
  local ctl = G.ANIMS.controllers["ChanceEffect_" .. self.effect]
  if not ctl then return nil end
  local st = ctl[self.state]
  if not st then return nil end
  local clip = st.clip and G.find_clip(st.clip)
  local t = core.now() - self.t0
  if clip and not clip.loop and t >= clip.len then
    if st.next then self:play(st.next) return self:current_clip(G) end
    if self.state == C._ANIM_OUT then self.effect = nil return nil end
  end
  if not clip and st.next then self:play(st.next) return self:current_clip(G) end
  return st.clip, t
end

return C
