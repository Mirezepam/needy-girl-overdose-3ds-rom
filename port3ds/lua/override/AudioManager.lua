-- AudioManager: SoundType -> clip (data/sounds.lua, resolved from the game's SoundMaster).
-- Long clips stream as Ogg on the BGM channel; short ones are cached PCM effects.
local core = require("runtime.core")
local C = class("AudioManager", "SingletonMonoBehaviour")

local sounds = require("data.sounds")
local se_cache, se_order = {}, {}
local MAX_SE = 48

function C:__fields()
  self.currentBgm = nil
  self.bgmVolume = 0.8
  self.seVolume = 0.9
  self._instance = self
end

local function clip_of(id)
  local s = sounds[id]
  return s and s[1] ~= "" and s[1] or id
end

local function is_bgm(id)
  local s = sounds[id]
  return (s and s[2]:sub(1, 3) == "BGM") or sys.exists(sys.data .. "snd/" .. clip_of(id) .. ".ogg")
end

function C:play_se_clip(clip, vol)
  local id = se_cache[clip]
  if not id then
    id = sys.se_load(sys.data .. "snd/" .. clip .. ".pcm")
    if not id then
      -- some short clips were long enough to be stored as ogg: play them on the BGM channel
      if sys.exists(sys.data .. "snd/" .. clip .. ".ogg") then sys.bgm_play(sys.data .. "snd/" .. clip .. ".ogg", false) end
      return
    end
    se_cache[clip] = id
    se_order[#se_order + 1] = clip
    if #se_order > MAX_SE then
      local old = table.remove(se_order, 1)
      sys.se_free(se_cache[old]); se_cache[old] = nil
    end
  end
  sys.se_play(id, (vol or 1) * self.seVolume)
end

function C:PlaySeByType(t) if t and t ~= NULL then self:play_se_clip(clip_of(t)) end return NULL end
C.PlaySeById = C.PlaySeByType
function C:PlaySe(name) self:play_se_clip(name) return NULL end
function C:PlaySeByTypeAsync(t) self:PlaySeByType(t); core.wait_ms(500) end
C.PlaySeAsync = C.PlaySeByTypeAsync
C.PlaySeByIdAsync = C.PlaySeByTypeAsync
C.PlayBankByType = C.PlaySeByType
C.PlayBank = C.PlaySe
C.PlayBankById = C.PlaySeByType

function C:PlayBgmByType(t, isLoop)
  if not t or t == NULL then return NULL end
  local clip = clip_of(t)
  if not is_bgm(t) then self:play_se_clip(clip); return NULL end
  if self.currentBgm == t then return NULL end
  self.currentBgm = t
  -- the original loops BGM sources set up as looping; the default argument is false but most BGM loop
  sys.bgm_play(sys.data .. "snd/" .. clip .. ".ogg", true)
  sys.bgm_volume(self.bgmVolume)
  return NULL
end
C.PlayBgmById = C.PlayBgmByType
function C:PlayBgm(name) return self:PlayBgmByType(name) end
function C:PlayBgmOneShotAsync(t) self:PlayBgmByType(t, false) end

function C:StopBgm() sys.bgm_stop(); self.currentBgm = nil end
function C:StopByType(t) if t == self.currentBgm then self:StopBgm() end return NULL end
C.Stop = C.StopByType
function C:StopAll() self:StopBgm() end
function C:IsPlayingByType(t) return self.currentBgm == t end
function C:IsPlaying() return self.currentBgm ~= nil end
C.__getters.PlayingBgm = function(self) return self.currentBgm end
function C:ChangeMasterVolume(v) self.bgmVolume = v; sys.bgm_volume(v) end
function C:ChangeSeVolume(v) self.seVolume = v end
function C:ChangeVolume(cat, v) if tostring(cat):find("BGM") then self:ChangeMasterVolume(v) else self.seVolume = v end end
function C:FetchPlayingAudioByType() return NULL end

C.Instance = C
return C
