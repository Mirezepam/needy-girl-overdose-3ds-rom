-- NEEDY GIRL OVERDOSE 3DS: Lua entry point (called by source/main.c).
local core = require("runtime.core")
-- the log always goes to the SD (the data may be read from the read-only RomFS)
core.logfile = io.open("sdmc:/3ds/needy3ds/log.txt", "w")
LOG("boot", _VERSION, sys.is_new3ds() and "New3DS" or "Old3DS", "data:", sys.data)

core.load_index(require("gen._index"))
local enums = require("enums")
core.set_enums(enums)
core.enums = enums
require("runtime.rx")
require("runtime.unity")
require("runtime.data")
local G = require("runtime.gfx")
local I = require("runtime.input")
-- Old 3DS: keep the texture cache small; New 3DS has room for more animation frames
G.set_budget(sys.is_new3ds() and 40 * 1024 * 1024 or 18 * 1024 * 1024)
math.randomseed(sys.time())
-- long-lived data (text tables, class modules) dominates the heap: generational GC is much cheaper
collectgarbage("generational")

local ui = require("ui.main")

game = {}

function game.init()
  ui.init()
end

-- on-screen profiler (toggle with L+R+SELECT): Lua milliseconds per frame
local prof = { on = false, u = 0, d = 0, n = 0, show = "" }
local ticks = sys.ticks or function() return 0 end

-- the system keyboard is an applet: opening it while the GPU frame is being built (any draw
-- code) can hang or crash a real console when it returns, so draw code only asks for it with
-- core.keyboard(hint, maxLen, callback) and it opens here, between frames
function core.keyboard(hint, maxLen, cb) core.kb_request = { hint = hint, max = maxLen, cb = cb } end

function game.update(dt, down, held, up, tx, ty)
  local t0 = ticks()
  local kb = core.kb_request
  if kb then
    core.kb_request = nil
    kb.cb(sys.keyboard(kb.hint, "", kb.max))
  end
  I.update(dt, down, held, up, tx, ty)
  if I.isheld(I.KEY.L) and I.isheld(I.KEY.R) and I.pressed(I.KEY.SELECT) then prof.on = not prof.on end
  core.update(dt)
  ui.update(dt)
  prof.u = prof.u + (ticks() - t0)
end

function game.draw(screen)
  local t0 = ticks()
  ui.draw(screen)
  prof.d = prof.d + (ticks() - t0)
  if screen == 1 then
    prof.n = prof.n + 1
    if prof.n >= 30 then
      prof.show = string.format("upd %.1fms draw %.1fms lua %dKB err %d", prof.u / prof.n, prof.d / prof.n, math.floor(collectgarbage("count")), core.error_count)
      prof.u, prof.d, prof.n = 0, 0, 0
    end
    if prof.on then sys.rect(0, 0, 320, 12, 0x000000c0); sys.text(prof.show, 2, 1, 0x80ff80ff) end
  end
end

function game.shutdown()
  if core.logfile then core.logfile:close() end
end
