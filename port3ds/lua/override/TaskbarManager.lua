-- Taskbar interactivity gate: while false the bottom screen desktop ignores input (events running).
local core = require("runtime.core")
local C = class("TaskbarManager", "SingletonMonoBehaviour")
-- TaskBarObj: the taskbar scene object (its children, e.g. TaskManagerShortcut, can be switched
-- off by the story); TaskBarGroup: its CanvasGroup (alpha 0 hides the bar)
function C:__fields()
  self.interactive = true
  self.TaskBarObj = core.ui_find("Taskbar")
  self.TaskBarGroup = self.TaskBarObj:GetComponent("CanvasGroup")
end
function C:SetTaskbarInteractive(v) self.interactive = v end
return C
