-- Modal dialogs (bottom screen, centered). Same behaviour as TimePassDialog.cs, EndingDialog.cs,
-- ShutDownDialog.cs and RebootDialog.cs.
local core = require("runtime.core")
local G = require("runtime.gfx")
local T = require("ui.theme")
local c = T.c

local M = {}
local function lang() return Settings.CurrentLanguage.Value end
local function st(id) local s = NgoEx.SystemTextFromType(id, lang()); return (s ~= NULL and s ~= "") and s or id end

local pending = {}
core.views.TimePassDialog = { pending = pending, setType = function(_, ac, a) pending.ac, pending.a = ac, a end }

local function reboot()
  Settings.saveNumber = 0
  Settings.nowSaveFile = ""
  Settings.isBackToLoad = false
  game.reboot = true
end
core.on_load_scene = function(name) reboot() end

local KINDS = {
  TimePassDialog = function()
    return st("System_AlertHaishin"), st("Dialog_OK"), st("Dialog_Cancell"), function(w)
      WindowManager:Close(w)
      local ac, a = pending.ac, pending.a
      spawn(function() EventManager:ExecuteActionConfirmed(ac, a) end)
    end
  end,
  EndingDialog = function()
    local ok, txt = pcall(NgoEx.ReasonTextFromEDType, EventManager.nowEnding, lang())
    if not ok then txt = "" end
    local ok = EventManager.nowEnding == "Ending_Ideon" and st("System_Thankyou") or st("Dialog_OK")
    return (txt ~= NULL and txt or ""), ok, nil, function(w) reboot() end
  end,
  ShutDownDialog = function()
    return st("Start_Alert_ShutDown"), st("Dialog_OK"), st("Dialog_Cancell"), function() game.quit = true end
  end,
  RebootDialog = function()
    return st("System_Reboot"), st("Dialog_OK"), st("Dialog_Cancell"), function() reboot() end
  end,
}

function M.draw(w)
  local def = KINDS[w.app]
  local text, ok, cancel, onOk
  if def then text, ok, cancel, onOk = def() else text, ok = w.app, "OK" end
  T.dim(320)
  local _, th = G.measure(text, 1, 252)
  local h = math.max(70, th + 50)
  local x, y = 26, (240 - h) / 2
  local cx, cy, cw = T.window(x, y, 268, h, w.app == "EndingDialog" and (({ SP = "Fin", EN = "The End", JP = "おしまい" })[lang()] or "Fin") or "Windose")
  G.text(text, cx + 6, cy + 4, c.ink, 1, 252)
  local by = y + h - 28
  if cancel then
    if T.button("dlg_ok", x + 20, by, 110, 22, ok, { center = true, fill = c.pink }) then if onOk then onOk(w) end end
    if T.button("dlg_no", x + 138, by, 110, 22, cancel, { center = true }) then WindowManager:Close(w) end
  else
    if T.button("dlg_ok", x + 79, by, 110, 22, ok, { center = true, fill = c.pink }) then
      if onOk then onOk(w) else WindowManager:Close(w) end
    end
  end
end

return M
