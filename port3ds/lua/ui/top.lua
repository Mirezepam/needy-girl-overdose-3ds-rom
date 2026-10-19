-- TOP SCREEN (400x240): the world you watch. HUD + Ame's webcam at 1:1 + scenes and overlays.
-- Never interactive (docs/PANTALLAS.md).
local core = require("runtime.core")
local G = require("runtime.gfx")
local T = require("ui.theme")
local c = T.c

local M = {}
local anim = { name = "stream_ame_idle", t0 = 0 }
local stats = {}          -- type -> {value, shown, diff, flash}
local HUD_STATS = { { "Follower", "Seg", 0xffffffff }, { "Love", "Cariño", 0xffa8d8ff },
                    { "Stress", "Estrés", 0xffb070ff }, { "Yami", "Mente", 0xc8a0ffff } }
local graph_sample          -- (TaskManager graphs, defined below)
local video = nil         -- {id, fps, frames, t0, w, h, app}
local live

local function lang() return Settings.CurrentLanguage.Value end

function M.init()
  live = require("ui.live")
end

-- App_Webcam (the view game code reaches through GetNakamiFromApp(Webcam):GetComponent).
-- PlayAnim keeps a looping clip running when asked for it again (the original only swaps the
-- override clip when it changes), non-looping clips hold their last frame,
-- handspinner1 chains into handspinner2, one-shots return to the previous clip.
local webcam = core.views.App_Webcam or {}
webcam.bgY = 0
core.views.App_Webcam = webcam
local function clip_loops(name)
  local cl = G.find_clip(name)
  return cl and cl.loop
end
function webcam:PlayAnim(name)
  if type(name) ~= "string" or #name <= 1 then return end
  if name == anim.name and clip_loops(name) then return end
  anim.name, anim.t0 = name, core.now()
end
function webcam:PlayAnimOneShot(name) anim.name, anim.t0 = name, core.now() end
setmetatable(webcam, { __index = function(t, k) if k == "CurrentAnim" then return anim.name end end })
function webcam:Yusayusa()
  anim.name, anim.t0 = "stream_ame_h_heart", core.now()
  for _ = 1, 8 do
    webcam.bgY = -5
    core.wait_ms(200)
    AudioManager:PlaySeByType("SE_piyo")
    webcam.bgY = 0
    core.wait_ms(200)
  end
end
function webcam:Nade()
  if EventManager.isHorror or anim.name == "stream_ame_h_heart" then return end
  if WebCamManager.hidegirl and WebCamManager.hidegirl.Value then return end
  if anim.name:find("^stream_ame_out_") then return end
  AudioManager:PlaySeByType("SE_nadenade_1")
  if not anim.name:find("^stream_ame_hair_") then WebCamManager:happy() end
end

local subscribed = false
local function subscribe()
  if subscribed or not WebCamManager._currentAnim then return end
  subscribed = true
  WebCamManager._currentAnim:Subscribe(function(name)
    if name and name ~= NULL then webcam:PlayAnim(name) end
  end)
  if WebCamManager.OnAnimOneShot then
    WebCamManager.OnAnimOneShot:Pairwise():Subscribe(function(pair)
      spawn(function()
        local pre = anim.name
        local cur = pair.Current
        webcam:PlayAnimOneShot(cur.Key)
        core.wait_ms(cur.Value)
        webcam:PlayAnim(pre)
      end)
    end)
  end
end

-- bgView(): no chair before day 11, silver / gold shield backgrounds, random screensaver on the PC
local bgv = { day = -1 }
local function bg_view()
  local day = StatusManager:GetStatus("DayIndex")
  if day == bgv.day then return end
  bgv.day = day
  local fol = StatusManager:GetStatus("Follower")
  bgv.nochair = day < 11
  if fol > 100000 and day > 14 then bgv.bg = "bg_stream_shield_silver" end
  if fol > 1000000 and day > 27 then bgv.bg = "bg_stream_shield_gold" end
  bgv.saver = EventManager.nowEnding == "Ending_None" and not EventManager.isHorror
  bgv.saverImg = "bg_stream_screensaver_" .. math.random(1, 3)
end

local function stat_update()
  for _, s in ipairs(HUD_STATS) do
    local v = StatusManager:GetStatus(s[1])
    local st = stats[s[1]]
    if not st then stats[s[1]] = { value = v, diff = 0, flash = -10 }
    elseif v ~= st.value then
      st.diff = v - st.value
      st.value = v
      st.flash = core.now()
    end
  end
end

function M.update(dt)
  if not StatusManager.statuses then return end
  subscribe()
  stat_update()
  graph_sample()
  -- video windows (psyche / media player)
  local tw = WindowManager.topWindow and WindowManager:topWindow()
  if tw and tw.kind == "video" then
    if not video or video.app ~= tw then
      if video then sys.video_close(video.id) end
      local name = tw.app == "MediaPlayer" and "INTERNETOVERDOSE" or ("psyche" .. math.random(1, 32))
      local id, w, h, fps, frames = sys.video_open(sys.data .. "vid/" .. name .. ".etv")
      video = id and { id = id, w = w, h = h, fps = fps, frames = frames, t0 = core.now(), app = tw } or { app = tw }
    end
  elseif video then
    if video.id then sys.video_close(video.id) end
    video = nil
  end
end

-- ------------------------------------------------------------------ pieces
local function daypart_sprite()
  local p = StatusManager:GetStatus("DayPart")
  return ({ [0] = "noon", [1] = "evening", [2] = "night" })[p] or "night"
end

local function fmt_num(n)
  local s = tostring(math.floor(n))
  return (s:reverse():gsub("(%d%d%d)", "%1."):reverse():gsub("^%.", ""))
end

local function draw_hud()
  G.rect(0, 0, 400, 14, 0x2a1f4ae0)
  local day = StatusManager:GetStatus("DayIndex")
  local dp = daypart_sprite()
  G.draw("icon_watch_" .. dp, 3, 1, { fit = { 12, 12 } })
  local dtext = NgoEx.DayText(day, lang())
  if dtext == NULL or dtext == nil or dtext == "" then dtext = "Día " .. day end
  G.text(dtext, 17, 2, c.white)
  local x = 96
  for _, s in ipairs(HUD_STATS) do
    local st = stats[s[1]]
    if st then
      local since = core.now() - st.flash
      local col = c.white
      if since < 2.5 then col = (st.diff > 0) and c.mint or c.red end
      local lw = G.measure(s[2])
      G.text(s[2], x, 2, 0xb8aee0ff)
      local txt = s[1] == "Follower" and fmt_num(st.value) or tostring(st.value)
      G.text(txt, x + lw + 4, 2, since < 2.5 and col or s[3])
      if since < 2.5 then
        local d = (st.diff > 0 and "+" or "") .. (s[1] == "Follower" and fmt_num(st.diff) or st.diff)
        G.rect(x + lw, 15, G.measure(d) + 8, 12, 0x00000090)
        G.text(d, x + lw + 4, 15, col)
      end
      x = x + lw + (s[1] == "Follower" and 62 or 32)
    end
  end
  if core.fast then G.text(">>", 360, 2, c.yellow) end
  local n = NotificationManager.items and #NotificationManager.items or 0
  if n > 0 then
    G.rect(380, 1, 18, 12, c.red)
    G.text_center(tostring(n), 389, 2, c.white)
  end
end

local function draw_sidebars()
  local dp = daypart_sprite()
  local name = "bg_side_bar_" .. dp .. "2"
  local sw, sh = G.size(name)
  if sw == 0 then G.rect(0, 14, 26, 226, c.lilac); G.rect(374, 14, 26, 226, c.lilac) return end
  local s = 226 / sh   -- keep the aspect ratio: scale to the height and show the central strip
  local off = (sw * s - 26) / 2
  G.clip(0, 14, 26, 226); G.draw(name, -off, 14, { scale = s }); G.unclip()
  G.clip(374, 14, 26, 226); G.draw(name, 374 - off, 14, { scale = s }); G.unclip()
end

-- App_Webcam: Ame's room (bg_stream) with her animation on top, clips at their original timing
local function draw_webcam()
  G.rect(26, 14, 348, 226, 0x101018ff)
  bg_view()
  G.clip(26, 14, 348, 226)
  local by = 13 + webcam.bgY
  G.draw(bgv.bg or "bg_stream", 26, by)
  if bgv.nochair then G.draw("bg_stream_no_chair", 26, by) end
  if bgv.saver then G.draw(bgv.saverImg, 26, by) end
  local hide = WebCamManager.hidegirl and WebCamManager.hidegirl.Value
  if not hide then
    local t = core.now() - anim.t0
    local cl = G.find_clip(anim.name)
    if anim.name == "stream_ame_handspinner1" and cl and t >= cl.len then webcam:PlayAnim("stream_ame_handspinner2"); t = 0 end
    if not G.play(anim.name, t, 26, 13) then
      G.play("stream_ame_idle", t, 26, 13)
    end
  end
  G.unclip()
end

-- App_TaskManager (GraphManager rows): status icon, sky-blue label, ink value, gray max and a
-- 30-bar history graph (#5bb4e1 on #ddbeed) sampled every 4 s; followers show only the number
local STAT_ROWS = { { "Follower", "icon_status_follower" }, { "Stress", "icon_status_stress" },
                    { "Love", "icon_status_love" }, { "Yami", "icon_status_yami" } }
local graph = { t = 0 }
function graph_sample()
  if core.now() - graph.t < 4 then return end
  graph.t = core.now()
  for _, r in ipairs(STAT_ROWS) do
    local h = graph[r[1]] or {}
    graph[r[1]] = h
    h[#h + 1] = StatusManager:GetStatus(r[1]) / math.max(1, StatusManager:GetMaxStatus(r[1]))
    if #h > 30 then table.remove(h, 1) end
  end
end

local function draw_stats_panel()
  local title = NgoEx.SystemTextFromType("Window_TaskManager", lang())
  if title == NULL or title == "" then title = "Administrador de tareas" end
  local x, y, w, h = T.window(196, 18, 178, 126, title, "icon_taskbar_taskmanager")
  G.rect(x, y, w, h, c.paper)
  for i, r in ipairs(STAT_ROWS) do
    local v = StatusManager:GetStatus(r[1])
    local max = StatusManager:GetMaxStatus(r[1])
    local yy = y + 2 + (i - 1) * 24
    G.draw(r[2], x + 2, yy, { fit = { 20, 20 } })
    local label = NgoEx.StatusLabelFromType(r[1], lang())
    G.text((label ~= NULL and label ~= "") and label or r[1], x + 26, yy, c.sky, 1, 120, 1)
    if r[1] == "Follower" then
      G.text(fmt_num(v), x + 26, yy + 11, c.ink)
    else
      G.text(tostring(v), x + 26, yy + 11, c.ink)
      G.text("/" .. max, x + 50, yy + 11, 0x999999ff)
      -- history graph
      local gx, gy, gw, gh = x + 86, yy + 2, w - 88, 19
      G.rect(gx, gy, gw, gh, 0xddbeedff)
      local hist = graph[r[1]] or {}
      local bw = gw / 30
      for k = 1, 30 do
        local f = hist[#hist - 30 + k] or 0
        if f > 0 then
          local bh = math.max(1, gh * math.min(1, f))
          G.rect(gx + (k - 1) * bw, gy + gh - bh, math.max(1, bw - 0.5), bh, c.sky)
        end
      end
    end
  end
end

local function draw_scene(w)
  local k = w.kind
  if k == "train" then
    G.rect(26, 14, 348, 226, 0x1a1530ff)
    local name = ({ Train = "OdekakeAnimation", Train_twilight = "OdekakeAnimation_evening", Train_night = "OdekakeAnimation_night", Train_Ginga = "OdekakeAnimation_galaxy" })[w.app]
    if not G.play(name or "OdekakeAnimation", core.now() - w.opened, 200, 127, { ax = 0.5, ay = 0.5, fit = { 348, 226 } }) then
      G.draw("odekake_map_base", 200, 127, { ax = 0.5, ay = 0.5, fit = { 348, 226 } })
    end
  elseif k == "daypart" then
    G.rect(26, 14, 348, 226, 0x000000c0)
    local i = tonumber(w.app:sub(-1)) or 0
    G.draw("icon_watch_" .. (({ [0] = "noon", "evening", "night", "night" })[i]), 200, 100, { ax = 0.5, ay = 0.5, scale = 3 })
  elseif k == "sleep" then
    local a = math.min(1, (core.now() - w.opened) / 1.5)
    G.rect(26, 14, 348, 226, math.floor(a * 230))
  elseif k == "calling" then
    G.rect(26, 14, 348, 226, 0xf7e6ffff)
    G.draw("bg_line_call", 200, 127, { ax = 0.5, ay = 0.5, fit = { 300, 220 } })
    G.draw("icon_jine_ame", 200, 100, { ax = 0.5, ay = 0.5, scale = 2 })
  elseif k == "video" then
    G.rect(0, 0, 400, 240, 0x000000ff)
    if video and video.id then
      local f = math.floor((core.now() - video.t0) * video.fps)
      if f >= video.frames then f = f % video.frames end
      sys.video_show(video.id, f)
      local s = math.min(400 / video.w, 240 / video.h)
      sys.video_draw(video.id, (400 - video.w * s) / 2, (240 - video.h * s) / 2, s)
    end
    return true
  elseif k == "live" then
    live.draw_top()
    return true
  elseif k == "pictures" then
    local img = rawget(w, "image") or (core.views.ImageViewer and core.views.ImageViewer.current)
    G.rect(26, 14, 348, 226, 0x000000ff)
    if img then G.draw(img, 200, 127, { ax = 0.5, ay = 0.5, fit = { 348, 226 } }) end
  end
  return false
end

local function draw_toast()
  local items = NotificationManager.items
  if not items or #items == 0 then return end
  local n = items[#items]
  local age = core.now() - n.born
  if age > 4 then return end
  local slide = math.min(1, age * 4)
  local x = 400 - 190 * slide
  T.panel(x, 20, 182, 34, c.ame)
  G.draw(n.app == "Jine" and "icon_taskbar_jine" or (n.app == "Poketter" and "icon_taskbar_poketter" or "icon_window_mail"), x + 4, 25, { fit = { 22, 22 } })
  G.text(n.text, x + 30, 24, c.ink, 1, 148, 2)
end

local function draw_tooltip()
  local tip = TooltipManager.current
  if not tip then return end
  local _, h = G.measure(tip.text, 1, 330)
  local y = 236 - h - 10
  T.panel(30, y, 340, h + 8, tip.kind == "tutorial" and c.yellow or c.paper)
  G.text(tip.text, 35, y + 4, c.ink, 1, 330)
end

local function draw_effects()
  local pe = PostEffectManager
  -- "Anmaku" is a darkening post effect (vignette), not a full black curtain
  if pe.anmaku and pe.anmaku > 0 then
    local w = math.min(1, pe.anmaku)
    G.rect(0, 0, 400, 240, math.floor(w * 110))
    for i = 0, 5 do
      local a = math.floor(w * (90 - i * 15))
      G.rect(0, 14 + i * 6, 400, 6, a); G.rect(0, 234 - i * 6, 400, 6, a)
    end
  end
  if pe.effect and pe.weight and pe.weight > 0 then
    local w = math.min(1, pe.weight)
    local t = core.now()
    -- cheap stand-ins for the original shaders: tinted scanlines + jitter bands
    for y = 14, 240, 4 do G.rect(0, y, 400, 1, math.floor(40 * w)) end
    if math.random() < 0.3 * w then
      local by = math.random(14, 230)
      G.rect(0, by, 400, math.random(2, 8), (math.random(0, 0xffffff) << 8) | math.floor(90 * w))
    end
    if tostring(pe.effect):find("Yami") or tostring(pe.effect):find("Horror") then G.rect(0, 0, 400, 240, 0x40001000 | math.floor(60 * w)) end
  end
  for _, w in ipairs(WindowManager:fxWindows()) do
    require("ui.fx").draw_top(w)
  end
  -- ChanceEffectCanvas: animated columns at both sides (right one mirrored)
  local clip, t = ChanceEffectController:current_clip(G)
  if clip then
    G.play(clip, t, 0, 0, { w = 50, h = 240 })
    G.play(clip, t, 400, 0, { w = 50, h = 240, flip = true })
  end
end

function M.draw()
  if not StatusManager.statuses then G.rect(0, 0, 400, 240, 0x000000ff) return end
  G.begin_frame()
  local tw = WindowManager:topWindow()
  local full = false
  draw_sidebars()
  draw_webcam()
  if tw and tw.kind ~= "webcam" and tw.kind ~= "stats" then full = draw_scene(tw) end
  -- the focused bottom app can show its visual content up here (tweet pictures, documents...)
  local fb = WindowManager.focusBottom
  local fmod = fb and require("ui.bottom").app_module(fb.kind)
  if not full and fmod and fmod.draw_top then fmod.draw_top(fb) end
  if not full then draw_hud() end
  if tw and tw.kind == "stats" and core.now() - tw.opened < 3 then draw_stats_panel() end
  local stw = WindowManager:find("TaskManager")
  if stw and stw ~= tw and core.now() - stw.opened < 3 then draw_stats_panel() end
  draw_effects()
  draw_toast()
  draw_tooltip()
end

return M
