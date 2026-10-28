-- EventManager.CallEnding -> the endingBlue screen (EndingManager): blue screen with SE_bluescreen,
-- "ENDING", the ending's name and a block per ending (seen / this one / not yet). It records the
-- ending in Settings.mitaEnd; any tap goes back to the title, except after Ending_Jisatu, whose
-- tap resumes the game (Event_Rentan_Comeback).
local core = require("runtime.core")
local G = require("runtime.gfx")
local I = require("runtime.input")
local T = require("ui.theme")
local c = T.c

local M = {}
local state = nil
local BLUE = 0x2b44c0ff

local function ending_name(e)
  local ok, p = pcall(NgoEx.EndingFromType, e)
  if not ok or not p or p == NULL then return e end
  local lang = Settings.CurrentLanguage.Value
  local field = ({ JP = "EndingNameJp", EN = "EndingNameEn", SP = "EndingNameSp" })[lang] or "EndingNameEn"
  local n = p[field]
  return (n and n ~= NULL and n ~= "") and n or e
end

local function all_endings()
  local list = {}
  local ok, enums = pcall(require, "enums")
  local E = ok and enums and enums.EndingType
  for name, v in pairs(E or {}) do
    if name ~= "Ending_None" and name ~= "Ending_Completed" and name ~= "Ending_NetShut" then
      list[#list + 1] = { name = name, v = v }
    end
  end
  table.sort(list, function(a, b) return a.v < b.v end)
  return list
end

-- (seen, total) over the same ending list the blue screen's grid shows
function M.progress()
  local list = all_endings()
  local seen = 0
  for _, e in ipairs(list) do
    if Settings.mitaEnd and Settings.mitaEnd:Contains(e.name) then seen = seen + 1 end
  end
  return seen, #list
end

function M.show()
  local e = EventManager.nowEnding
  WindowManager:CleanAll()
  CursorManager:SetCursorShowHide(false)
  PostEffectManager:ResetShader()
  AudioManager:StopAll()
  AudioManager:PlaySeByType("SE_bluescreen")
  local seen = {}
  for _, x in EACH(Settings.mitaEnd) do seen[tostring(x)] = true end
  if e ~= "Ending_Jisatu" then
    Settings.mitaEnd:Add(e)
    spawn(function() Settings:Save() end)
  end
  state = { ending = e, name = ending_name(e), seen = seen, list = all_endings(), t0 = core.now() }
end

function M.active() return state ~= nil end
function M.hide() state = nil end

local function proceed()
  local e = state.ending
  state = nil
  AudioManager:StopAll()
  if e == "Ending_Jisatu" then
    EventManager:AddEvent_1("Event_Rentan_Comeback")
    return
  end
  EventManager.nowEnding = "Ending_None"
  -- EndingManager: the ChooseZip scene (EndingOmake) until the 30 zips are open, then BiosToLoad
  if not Settings:checkAllZipUnlocked() then
    state = { zip = true, t0 = core.now() }
    return
  end
  require("ui.bottom").app_module("dialog").reboot()
end

-- EndingOmake: 30 EndingZip buttons (an opened one is not interactable); opening one shows its
-- fan art (every 30th of the @ list from zip-1, SE_tweet_load 120 ms apart), Settings.OpenZip
-- unlocks them in My Pictures, and continue goes to BiosToLoad
local function draw_zip()
  G.rect(0, 0, 320, 240, BLUE)
  local z = state
  if not z.open then
    for i = 1, 30 do
      local x, y = 12 + ((i - 1) % 6) * 50, 12 + math.floor((i - 1) / 6) * 40
      local done = Settings.unLockedZip:Contains(i)
      if done then G.push(0, 0, 1, 0.4) end
      G.draw("icon_desktop_folder_zip", x + 9, y, { fit = { 28, 28 } })
      G.text_center(tostring(i), x + 23, y + 26, c.white)
      if done then G.pop() end
      local id = "zip" .. i
      if I.focusable(id, x, y, 46, 38) then T.focus_ring(x, y, 46, 38) end
      if not done and (I.tapped(x, y, 46, 38) or I.activated(id)) then
        AudioManager:PlaySeByType("SE_piporo")
        local list, ids = ImageViewerHelper.LoadFanArtList(), List.new()
        local pics = {}
        for k = i - 1, list.Count - 1, 30 do
          local r = list:__idx(k)
          pics[#pics + 1] = r.FileName
          ids:Add(r.FileName)
        end
        z.open, z.pics, z.shown, z.t = i, pics, 0, core.now()
        Settings:OpenZip(i, ids)
      end
    end
    if Settings:checkAllZipUnlocked() and T.button("zip_continue", 130, 212, 60, 22, "▶", { center = true }) then
      require("ui.bottom").app_module("dialog").reboot()
    end
    return
  end
  -- the opened zip: its pictures appear one by one
  G.text(tostring(z.open), 8, 4, c.white)
  local due = math.floor((core.now() - z.t) / 0.12) + 1
  while z.shown < math.min(due, #z.pics) do
    z.shown = z.shown + 1
    AudioManager:PlaySeByType("SE_tweet_load")
  end
  for k = 1, z.shown do
    local x, y = 8 + ((k - 1) % 5) * 61, 20 + math.floor((k - 1) / 5) * 46
    G.rect(x, y, 58, 42, 0x000000ff)
    G.draw(z.pics[k], x + 29, y + 21, { ax = 0.5, ay = 0.5, fit = { 58, 42 } })
  end
  if T.button("zip_continue", 130, 212, 60, 22, "▶", { center = true }) then
    require("ui.bottom").app_module("dialog").reboot()
  end
end

function M.draw_top()
  G.rect(0, 0, 400, 240, BLUE)
  if state.zip then return end
  G.text("ENDING", 24, 30, c.white, 2)
  G.text(state.name, 24, 80, c.white, 1, 352)
  G.rect(24, 74, 352, 1, 0xffffff80)
end

function M.draw_bottom()
  if state.zip then return draw_zip() end
  G.rect(0, 0, 320, 240, BLUE)
  local n = #state.list
  local cols = 6
  local bw, bh = 46, 22
  local x0 = (320 - cols * (bw + 4)) / 2
  for i, it in ipairs(state.list) do
    local x = x0 + ((i - 1) % cols) * (bw + 4)
    local y = 20 + math.floor((i - 1) / cols) * (bh + 6)
    if it.name == state.ending then
      local on = math.floor(core.now() * 3) % 2 == 0
      G.rect(x, y, bw, bh, on and 0xff9fd6ff or c.white)
    elseif state.seen[it.name] then
      G.rect(x, y, bw, bh, c.white)
    else
      G.frame_rect(x, y, bw, bh, 0xffffff80)
    end
  end
  if core.now() - state.t0 > 1.5 and (I.tap or I.pressed(I.KEY.A)) then
    I.tap = nil
    proceed()
  end
end

-- EventManager.CallEnding (Unity: Instantiate(endingBlue) over the main panel)
local hooked = false
function M.hook()
  if hooked then return end
  local EM = core.resolve("EventManager")
  if EM == NULL or not EM then return end
  hooked = true
  EM.CallEnding = function(self) M.show() end
end

return M
