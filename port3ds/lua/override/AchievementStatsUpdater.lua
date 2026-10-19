-- Achievements are recorded locally (the endings list in Settings already tracks progress).
local C = class("AchievementStatsUpdater", "Object")
function C.UpdateStats(name) LOG("achievement", name) end
function C.UpdateEndingStats() end
return C
