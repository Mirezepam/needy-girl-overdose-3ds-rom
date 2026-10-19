-- Post effects (shaders in the original) become cheap screen overlays on 3DS.
local C = class("PostEffectManager", "SingletonMonoBehaviour")

function C:__fields() self.effect = nil; self.weight = 0; self.anmaku = 0; self._instance = self end
function C:SetShader(t) self.effect = t; if self.weight == 0 then self.weight = 1 end end
function C:SetShaderWeight_1(w) self.weight = w end
function C:SetShaderWeight_2(w, t) self.effect = t; self.weight = w end
function C:AnmakuWeight(w) self.anmaku = w end
function C:ResetShader() self.effect = nil; self.weight = 0; self.anmaku = 0 end
function C:ResetShaderCalmly_1() self:ResetShader() end
function C:ResetShaderCalmly_2() self:ResetShader() end
function C:MogoMogo(on) self.mogo = on end
function C:BloomLight() return NULL end
function C:Dispose() end
C.Instance = C
return C
