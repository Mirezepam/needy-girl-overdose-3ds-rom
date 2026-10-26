-- Ending_Meta's scene (EndingCover/castwindow, jimaku, meta + Metacover/Button1-2): Chouten's
-- stream window growing towards the player for 60 s, typed subtitles, then her hand over the
-- screen; the player answers with the two buttons. The event script drives the scene objects,
-- this draws them. Top: the window / hand and the subtitles. Bottom: the answer buttons.
local core = require("runtime.core")
local G = require("runtime.gfx")
local I = require("runtime.input")
local T = require("ui.theme")
local c = T.c

local M = {}
local t_cast = nil

local function obj(name) return core.ui_objects[name] end
local function active(name) local o = obj(name); return o and rawget(o, "_active") == true end

function M.active()
  return EventManager.nowEnding == "Ending_Meta" and (active("castwindow") or active("meta") or active("jimaku"))
end

-- subtitle text typed out (DOText: 0.3 s per character in Ending_Meta.Speak)
local function subtitle()
  local tmp = core.ui_find("jimakuText"):GetComponent("TMP_Text")
  local s = rawget(tmp, "text")
  if type(s) ~= "string" or s == "" then return nil end
  local t0 = rawget(tmp, "_t0") or 0
  local n = math.floor((core.now() - t0) / 0.3 * (core.fast and 6 or 1))
  local cut = utf8.offset(s, n + 1)
  return cut and s:sub(1, cut - 1) or s
end

function M.draw_top()
  G.rect(0, 0, 400, 240, 0x000000ff)
  if active("meta") then
    G.draw("stream_cho_meta", 200, 120, { ax = 0.5, ay = 0.5, fit = { 400, 240 } })
  elseif active("castwindow") then
    t_cast = t_cast or core.now()
    local k = 1 + 5 * math.min(1, (core.now() - t_cast) / 60)   -- DOScale(6, 60 s)
    local x, y, w, h = T.window(60, 16, 280, 200, "live", "icon_desktop_youtube")
    G.clip(x, y, w, h)
    local cx, cy = x + w / 2, y + h * 0.45
    G.draw("bg_stream", cx, cy, { ax = 0.5, ay = 0.5, scale = 0.75 * k })
    G.play("stream_cho_akaruku", core.now(), cx, cy, { ax = 0.5, ay = 0.5, scale = 0.75 * k })
    G.unclip()
  end
  local s = active("jimaku") and subtitle()
  if s then
    local tw, th = G.measure(s, 1, 340)
    G.rect(200 - tw / 2 - 6, 222 - th - 6, tw + 12, th + 6, 0x4d22cfcc)
    G.text(s, 200 - tw / 2, 222 - th - 3, c.white, 1, 340)
  end
end

local function button(name, x, y)
  if not active(name) then return end
  local go = core.ui_find(name)
  local label = rawget(go:GetComponent("TMP_Text"), "text") or "..."
  if T.button("meta_" .. name, x, y, 260, 30, label, { center = true }) then
    core.fire_pointer(go:GetComponent("Button"), "down")
  end
end

function M.draw_bottom()
  G.rect(0, 0, 320, 240, 0x000000ff)
  button("Button1", 30, 70)
  button("Button2", 30, 120)
end

-- the scene objects start hidden; the event shows them
for _, n in ipairs({ "castwindow", "jimaku", "meta", "Button1", "Button2" }) do core.ui_inactive[n] = true end

return M
