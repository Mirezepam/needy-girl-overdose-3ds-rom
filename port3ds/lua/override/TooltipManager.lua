-- Tooltips/tutorials: drawn on the TOP screen so the stylus never covers them (docs/PANTALLAS.md).
local core = require("runtime.core")
local C = class("TooltipManager", "SingletonMonoBehaviour")

function C:__fields() self.current = nil end

local function tip_text(t, extra)
  if extra and extra ~= "" then return extra end
  local p = NgoEx.getToolTip(t)
  if p and p ~= NULL then return NgoEx.GetToolTipText(p, Settings.CurrentLanguage.Value) end
  return tostring(t)
end

function C:show(text, kind) self.current = { text = text, kind = kind, t = core.now() } end
function C:Show_1(pos, t, homing, text) self:show(tip_text(t, text), "tip") end
function C:Show_2(t) self:show(tip_text(t), "tip") end
function C:ShowTutorial_1(t, text) self:show(tip_text(t, text), "tutorial") end
function C:ShowTutorial_2(pos, t, homing, text) self:show(tip_text(t, text), "tutorial") end
function C:ShowAction(a, cmd)
  if cmd and cmd ~= NULL then
    self:show(NgoEx.GetCommandDesc(cmd, Settings.CurrentLanguage.Value), "action")
    self.current.cmd = cmd
  end
end
function C:Hide() self.current = nil end
return C
