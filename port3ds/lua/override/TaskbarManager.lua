-- Taskbar interactivity gate: while false the bottom screen desktop ignores input (events running).
local C = class("TaskbarManager", "SingletonMonoBehaviour")
function C:__fields() self.interactive = true; self.TaskBarGroup = NULL; self.TaskBarObj = NULL end
function C:SetTaskbarInteractive(v) self.interactive = v end
return C
