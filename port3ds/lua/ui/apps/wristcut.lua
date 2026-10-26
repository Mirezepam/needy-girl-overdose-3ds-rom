-- The Darkness window = App_WristCut (WristcutView + WristcutPresenter): purple background, the
-- wrist, a pink bar sliding up and down (3 s each way); GO cuts where the bar is (SE_zubasi, a
-- scar stays), the label counts down from WristGO; after the 3 cuts (WristcutModel.FetchCutCount)
-- the finish ActionButton runs the Darkness action. Horror day 3 drives the same view by script
-- (OnGo without the buttons).
local core = require("runtime.core")
local G = require("runtime.gfx")
local I = require("runtime.input")
local T = require("ui.theme")
local c = T.c

local M = {}
local CUTS = 3
local RANGE = 70          -- bar travel (px) above / below the middle

local function new_button() return { gameObject = { _active = true, SetActive = function(self, v) self._active = v end } } end

local view = { kizu = {}, left = CUTS, t0 = 0, done = false, _goButton = new_button(), _finishButton = new_button() }
core.views.WristcutView = view

local function bar_offset()
  local t = (core.now() - view.t0) % 12
  -- Sequence(+targetY over 3 s, -targetY over 3 s) relative, looping: up, back, down, back
  local p = t / 3
  if p < 1 then return -RANGE * p
  elseif p < 2 then return -RANGE * (2 - p)
  elseif p < 3 then return RANGE * (p - 2)
  else return RANGE * (4 - p) end
end

function view:OnGo(day)
  if core.now() - (self.last_go or -100) > 10 and not self._goButton.gameObject._active then self.kizu = {} end
  self.last_go = core.now()
  self.kizu[#self.kizu + 1] = bar_offset()
  AudioManager:PlaySeByType("SE_zubasi")
end

local function reset()
  view.kizu, view.left, view.t0, view.done = {}, CUTS, core.now(), false
  view._goButton.gameObject._active, view._finishButton.gameObject._active = true, true
end
M.reset = reset

function M.draw(win, x0, y0, w0, h0)
  if rawget(win, "wrist_open") == nil then
    rawset(win, "wrist_open", true)
    -- a scripted use (horror day 3) hides GO and starts cutting right away: keep its cuts
    local scripted = not view._goButton.gameObject._active and view.last_go and core.now() - view.last_go < 3
    if not scripted then reset() end
  end
  local x, y, w, h = x0, y0, w0, h0
  G.rect(x, y, w, h, c.ink)
  local cx, cy = x + w / 2, y + h / 2 - 10
  G.rect(cx - 38, y, 76, h, 0xeedcbdff)
  for _, k in ipairs(view.kizu) do G.rect(cx - 30, cy + k - 1, 60, 3, 0xc0303aff) end
  if not view.done then G.rect(cx - 35, cy + bar_offset() - 1, 70, 2, 0xea9fe8ff) end
  if view._goButton.gameObject._active and not view.done then
    local label = view.left == CUTS and T.st("WristGO", "GO!") or tostring(view.left)
    if T.button("wrist_go", cx - 50, y + h - 34, 100, 22, label, { center = true }) then
      view:OnGo(StatusManager:GetStatus("DayIndex"))
      view.left = view.left - 1
      if view.left <= 0 then
        view.done = true
        spawn(function()
          core.wait_ms(80)
          CommandManager:CommandAction_2("Darkness")
        end)
      end
    end
  end
end

return M
