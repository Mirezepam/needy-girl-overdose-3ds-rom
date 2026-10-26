-- TOP SCREEN (400x240): the world you watch. HUD + Ame's webcam at 1:1 + scenes and overlays.
-- Never interactive (docs/PANTALLAS.md).
local core = require("runtime.core")
local G = require("runtime.gfx")
local T = require("ui.theme")
local c = T.c

local M = {}
local anim = { name = "stream_ame_idle", t0 = 0 }
local stats = {}          -- type -> {value, shown, diff, flash}
local HUD_STATS = { { "Follower", { es = "Seg", en = "Subs", ja = "登録" }, 0xffffffff },
                    { "Love", { es = "Cariño", en = "Love", ja = "好感" }, 0xffa8d8ff },
                    { "Stress", { es = "Estrés", en = "Stress", ja = "ストレス" }, 0xffb070ff },
                    { "Yami", { es = "Mente", en = "Dark", ja = "闇" }, 0xc8a0ffff } }
local graph_sample          -- (TaskManager graphs, defined below)
local video = nil         -- {id, fps, frames, t0, w, h, app}
local bankv = nil         -- bank opening video {win, name, id, w, h, fps, frames}
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
      local name = tw.app == "MV" and "INTERNETOVERDOSE" or ("psyche" .. math.random(1, 32))
      local id, w, h, fps, frames = sys.video_open(sys.data .. "vid/" .. name .. ".etv")
      video = id and { id = id, w = w, h = h, fps = fps, frames = frames, t0 = core.now(), app = tw } or { app = tw }
    end
  elseif video then
    if video.id then sys.video_close(video.id) end
    video = nil
  end
  if bankv and not (tw and tw == bankv.win) then
    if bankv.id then sys.video_close(bankv.id) end
    bankv = nil
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
  if dtext == NULL or dtext == nil or dtext == "" then dtext = T.st("Day_Live", "DÍA") .. " " .. day end
  G.text(dtext, 17, 2, c.white)
  local x = 96
  for _, s in ipairs(HUD_STATS) do
    local st = stats[s[1]]
    if st then
      local since = core.now() - st.flash
      local col = c.white
      if since < 2.5 then col = (st.diff > 0) and c.mint or c.red end
      local label = T.tr(s[2])
      local lw = G.measure(label)
      G.text(label, x, 2, 0xb8aee0ff)
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

-- Outing map (Odekake): odekake_map_base with a building per destination the menu offers and
-- the pin over the one under the stylus. Positions follow Tokyo's geography on the base map
-- (Yamanote loop, bay at the bottom right): the original layout prefab is not available.
local MAP_SPOTS = {
  OdekakeKichijoji = { "kichijoji", 22, 112 }, OdekakeNakano = { "nakano", 86, 182 },
  OdekakeShinjuku = { "shinjyuku", 160, 118 }, OdekakeIkebukuro = { "ikebukuro", 250, 58 },
  OdekakeHarajuku = { "harajyuku", 196, 210 }, OdekakeShibuya = { "shibuya", 206, 250 },
  OdekakeShimokitazawa = { "shimokitazawa", 104, 286 }, OdekakeIchigaya = { "ichigaya", 288, 150 },
  OdekakeJinbocho = { "jimbocho", 352, 196 }, OdekakeUeno = { "ueno", 446, 168 },
  OdekakeAkihabara = { "akihabara", 420, 212 }, OdekakeAsakusa = { "asakusa", 478, 128 },
  OdekakeOdaiba = { "odaiba", 418, 318 }, OdekakeToyosu = { "toyosu", 478, 304 },
  OdekakeHospital = { "hospital", 318, 238 }, OdekakeZikka = { "jikka", 26, 30 },
  OdekakeGinga = { "galaxy_station", 236, 6 }, OdekakeHikarigaokaPark = { nil, 290, 38 },
  OdekakeGisneyland = { nil, 486, 236 },
}
local function draw_outing_map(hover)
  local s = 348 / 524
  local ox, oy = 26, 14 + (226 - 356 * s) / 2
  G.rect(26, 14, 348, 226, 0x86c06eff)
  G.draw("odekake_map_base", ox, oy, { scale = s })
  local avail = require("ui.bottom").visible_actions or {}
  for a, sp in pairs(MAP_SPOTS) do
    if avail[a] and sp[1] then G.draw("odekake_map_" .. sp[1], ox + sp[2] * s, oy + sp[3] * s, { scale = s * 1.4 }) end
  end
  local sp = hover and MAP_SPOTS[hover]
  if sp then
    local bob = math.sin(core.now() * 6) * 2
    G.draw("odekake_map_pin", ox + sp[2] * s + 6, oy + sp[3] * s - 14 + bob, { scale = 1 })
    local title = CommandHelper.GetCommandTitle_3(hover, lang())
    if title and title ~= NULL then
      local tw = G.measure(title)
      T.panel(200 - tw / 2 - 8, 214, tw + 16, 18, c.white)
      G.text_center(title, 200, 217, c.ink)
    end
  end
end

-- package insert of a drug (YakujoUnit: name, dose, effects, side effects, Ame's memo), pink
-- headings (#e992c8) over ink text, like the right half of the App_Kusuri* windows
local function draw_insert(key)
  local function y(k) local v = NgoEx.yakujo(key, k, lang()); return (v ~= NULL and v) or "" end
  local function head(k) local v = NgoEx.yakujo("midasi", k, lang()); return (v ~= NULL and v) or k end
  local x0, y0, w0, h0 = T.window(60, 20, 280, 214, T.tr(T.YAKUJO_TITLE), "icon_desktop_okusuri")
  G.rect(x0, y0, w0, h0, c.white)
  local yy = y0 + 4
  G.text(y("namae"), x0 + 6, yy, c.ink, 1, w0 - 12, 2)
  yy = yy + 18
  for _, k in ipairs({ "tekiryo", "kounou", "hukusayou", "memo" }) do
    local body = y(k)
    if body ~= "" then
      G.text(head(k), x0 + 6, yy, 0xe992c8ff)
      local th = G.text(body, x0 + 6, yy + 12, c.ink, 1, w0 - 12, 3)
      yy = yy + 16 + math.max(12, th)
    end
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
    G.text((label ~= NULL and label ~= "") and label or r[1], x + 26, yy, c.sky, 1, w - 28, 1)
    if r[1] == "Follower" then
      G.text(fmt_num(v), x + 26, yy + 11, c.ink)
    else
      G.text(tostring(v), x + 26, yy + 11, c.ink)
      G.text("/" .. max, x + 50, yy + 11, 0x999999ff)
      -- history graph
      -- below the label line, so long labels ("Estado mental") stay readable
      local gx, gy, gw, gh = x + 86, yy + 11, w - 88, 11
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
    -- App_JINECall: black screen with the bg_line_call art (avatar, dots, answer / decline)
    G.rect(0, 0, 400, 240, 0x000000ff)
    G.draw("bg_line_call", 200, 120, { ax = 0.5, ay = 0.5, fit = { 400, 236 } })
    return true
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
  elseif k == "ending" then
    return require("ui.bottom").app_module("ending").draw_top()
  elseif k == "bank" then
    -- App_BankView: the stream opening animation (BankAnimation, English art outside Japanese,
    -- the black variant for the dark angel)
    local jp = Settings.CurrentLanguage.Value == "JP"
    local dark = (EventManager.alpha == "Angel" and EventManager.alphaLevel == 6) or EventManager.nowEnding == "Ending_DarkAngel"
    G.rect(0, 0, 400, 240, 0xffffffff)
    -- played as an ETC1 video (tools/export_bank.py); the sprite clip is only a fallback, it
    -- streams 31 atlas pages from the SD
    local vname = "bank_" .. (jp and "jp" or "eng") .. (dark and "_b" or "")
    if not bankv or bankv.win ~= w or bankv.name ~= vname then
      if bankv and bankv.id then sys.video_close(bankv.id) end
      local id, vw, vh, fps, frames = sys.video_open(sys.data .. "vid/" .. vname .. ".etv")
      bankv = { win = w, name = vname, id = id, w = vw, h = vh, fps = fps, frames = frames }
    end
    if bankv.id then
      local f = math.min(bankv.frames - 1, math.floor((core.now() - w.opened) * bankv.fps))
      sys.video_show(bankv.id, f)
      local s = math.min(400 / bankv.w, 240 / bankv.h)
      sys.video_draw(bankv.id, (400 - bankv.w * s) / 2, (240 - bankv.h * s) / 2, s)
    else
      local name = (jp and "BankAnimation" or "BankAnimation_Eng") .. (dark and "_B" or "")
      G.play(name, core.now() - w.opened, 200, 120, { ax = 0.5, ay = 0.5, fit = { 400, 240 } })
    end
    local skip = "▶SKIP"
    G.text(skip, 396 - G.measure(skip), 4, 0x4d22cf6f)
    return true
  elseif k == "ideon" then
    return require("ui.bottom").app_module("ideon").draw_top()
  elseif k == "pictures" then
    local img = rawget(w, "image") or (core.views.ImageViewer and core.views.ImageViewer.current)
    G.rect(26, 14, 348, 226, 0x000000ff)
    if img then G.draw(img, 200, 127, { ax = 0.5, ay = 0.5, fit = { 348, 226 } }) end
  end
  return false
end

local function draw_toast(ty)
  ty = ty or 20
  local items = NotificationManager.items
  if not items or #items == 0 then return end
  local n = items[#items]
  local age = core.now() - n.born
  if age > 4 then return end
  local slide = math.min(1, age * 4)
  local x = 400 - 190 * slide
  T.panel(x, ty, 182, 34, c.ame)
  G.draw(n.app == "Jine" and "icon_taskbar_jine" or (n.app == "Poketter" and "icon_taskbar_poketter" or "icon_window_mail"), x + 4, ty + 5, { fit = { 22, 22 } })
  G.text(n.text, x + 30, ty + 4, c.ink, 1, 148, 2)
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
  local blue = require("ui.bottom").app_module("endingblue")
  if blue.active() then blue.draw_top() return end
  local meta = require("ui.bottom").app_module("metacover")
  if meta.active() then meta.draw_top() return end
  local tw = WindowManager:topWindow()
  local full = false
  draw_sidebars()
  draw_webcam()
  if tw and tw.kind ~= "webcam" and tw.kind ~= "stats" then full = draw_scene(tw) end
  local bmenu, bhover = require("ui.bottom").current_menu()
  if not full and bmenu == "odekake" then draw_outing_map(bhover) end
  local B = require("ui.bottom")
  if not full and bmenu == "okusuri" and B.drug_shown then draw_insert(B.drug_shown) end
  -- the focused bottom app can show its visual content up here (tweet pictures, documents...)
  local fb = WindowManager.focusBottom
  local fmod = fb and require("ui.bottom").app_module(fb.kind)
  if not full and fmod and fmod.draw_top then fmod.draw_top(fb) end
  if not full then draw_hud() end
  local stats_shown = false
  if tw and tw.kind == "stats" and core.now() - tw.opened < 3 then draw_stats_panel(); stats_shown = true end
  local stw = WindowManager:find("TaskManager")
  if stw and stw ~= tw and core.now() - stw.opened < 3 then draw_stats_panel(); stats_shown = true end
  draw_effects()
  draw_toast(stats_shown and 150 or 20)   -- below the Task Manager panel while it shows
  -- Poem cover (Megaten, horror day 4): dark screen with the poem typed in the middle
  local ptext, pa
  if Poem.visible_text then ptext, pa = Poem.visible_text() end
  if pa and pa > 0 then
    G.rect(0, 0, 400, 240, math.floor(pa * 0xe8))
    for _ = 1, 4 do G.rect(math.random(0, 380), math.random(0, 236), math.random(20, 120), 1, 0xffffff00 | math.floor(pa * 40)) end
    if ptext and ptext ~= "" then
      local _, th = G.measure(ptext, 1, 340)
      G.text(ptext, 30, 120 - th / 2, 0xffffff00 | math.floor(pa * 255), 1, 340)
    end
  end
  draw_tooltip()
end

return M
