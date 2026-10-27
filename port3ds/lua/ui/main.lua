-- UI orchestrator: title screen -> game. Owns the per-screen draw dispatch.
local core = require("runtime.core")
local G = require("runtime.gfx")
local I = require("runtime.input")
local T = require("ui.theme")

local ui = { state = "title" }
core.views = {}

local title, top, bottom

function ui.init()
  title = require("ui.title")
  title.init(ui)
  -- development autoplay (sdmc:/3ds/needy3ds/autoplay.txt): start a new game in slot 3 and play
  -- never in a build that carries its data in the CIA (a test copy on a real console): a stray
  -- autoplay.txt on the SD would make the game play by itself
  if sys.data ~= "romfs:/" and sys.exists("sdmc:/3ds/needy3ds/autoplay.txt") then
    ui.autoplay = require("runtime.autoplay")
    ui.autoplay.log = function(...) LOG("[autoplay]", ...) end
    spawn(function() core.wait_ms(2500); ui.start_game({ lang = "es", slot = 3 }) end)
  end
end

function ui.start_game(opts)
  local boot = require("runtime.boot")
  top = require("ui.top")
  bottom = require("ui.bottom")
  top.init()
  bottom.init()
  T.click_se = function() AudioManager:PlaySeByType("SE_click") end
  ui.state = "game"
  boot.start_game(opts)
end

function ui.update(dt)
  if ui.state == "title" then title.update(dt)
  else
    top.update(dt)
    bottom.update(dt)
    if ui.autoplay then ui.autoplay.step() end
  end
end

function ui.draw(screen)
  G.screen = screen
  G.W = screen == 0 and 400 or 320
  if ui.state == "title" then title.draw(screen)
  elseif screen == 0 then top.draw()
  else bottom.draw() end
end

return ui
