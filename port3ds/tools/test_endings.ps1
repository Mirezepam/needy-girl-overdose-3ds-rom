# Puts the game (on day 2, through NGO_INJECT) in the state that makes the game's own logic pick
# each ending, lets the bot play on and reports errors and which ending dialog was reached.
# usage: powershell -File tools\test_endings.ps1 <lua54.exe> [name ...]
param([string]$Lua, [Parameter(ValueFromRemainingArguments = $true)][string[]]$Only)
Set-Location (Join-Path $PSScriptRoot "..")
$env:PATH = "C:\msys64\usr\bin;" + $env:PATH
$S = 'local S = StatusManager; local function set(t, v) S:UpdateStatusToNumber(t, v) end; '
$day29 = 'set("DayIndex", 29); '
$cases = [ordered]@{
  Grand     = $S + $day29 + 'set("Follower", 1200000); set("Love", 95); set("Yami", 90); NetaManager.usedAlpha:Add(NEW("AlphaLevel", 1, "Angel", 5))'
  Happy     = $S + $day29 + 'set("Follower", 1200000); set("Love", 95); set("Yami", 20)'
  Normal    = $S + $day29 + 'set("Follower", 600000); set("Love", 95); set("Yami", 20)'
  Yarisute  = $S + $day29 + 'set("Follower", 600000); set("Love", 30); set("Yami", 20)'
  Needy     = $S + $day29 + 'set("Follower", 3000); set("Love", 75); set("Yami", 75)'
  Sucide    = $S + $day29 + 'set("Follower", 3000); set("Love", 30); set("Yami", 75)'
  Work      = $S + $day29 + 'set("Follower", 3000); set("Love", 75); set("Yami", 30)'
  Bad       = $S + $day29 + 'set("Follower", 3000); set("Love", 30); set("Yami", 30)'
  Kyouso    = $S + $day29 + 'EventManager.isGedatsu = true'
  Healthy   = $S + 'set("Follower", 20000); set("Yami", 0)'
  Sukisuki  = $S + 'set("Follower", 20000); set("Love", 100)'
  Ntr       = $S + 'set("Follower", 20000); set("Love", 0)'
  Meta      = $S + 'set("Follower", 20000); EventManager.psycheCount = 5'
  Stressful = $S + 'set("Follower", 20000); set("Love", 50); S:UpdateStatusMaxToNumber("Stress", 120); set("Stress", 120); set("DayPart", 2)'
  Ideon     = $S + 'set("DayIndex", 20); set("Follower", 9999999)'
  Horror    = $S + 'set("DayIndex", 24); set("Follower", 200000); EventManager.isHakkyo = true; EventManager.isWristCut = true; S:UpdateStatusMaxToNumber("Stress", 120); set("Stress", 95)'
  Yami      = 'rawset(_G, "BOT_HOLD", 6000); NotificationManager.items = {}; EventManager:StartHaishin("Yamihaishin", 5, "none")'
  Av        = 'rawset(_G, "BOT_HOLD", 6000); NotificationManager.items = {}; EventManager:StartHaishin("Hnahaisin", 5, "none")'
  DarkAngel = 'rawset(_G, "BOT_HOLD", 3000); spawn(function() EventManager:AddEvent_1("Ending_DarkAngel") end)'
  Lust      = 'rawset(_G, "BOT_HOLD", 3000); spawn(function() EventManager:AddEvent_1("Ending_Lust") end)'
  Megaten   = 'rawset(_G, "BOT_HOLD", 3000); spawn(function() EventManager:AddEvent_1("Ending_Megaten") end)'
  Mibare    = 'rawset(_G, "BOT_HOLD", 3000); spawn(function() EventManager:AddEvent_1("Ending_Mibare") end)'
  NetShut   = 'rawset(_G, "BOT_HOLD", 3000); spawn(function() EventManager:AddEvent_1("Ending_NetShut") end)'
  KowaiInternet = 'rawset(_G, "BOT_HOLD", 3000); spawn(function() EventManager:AddEvent_1("Ending_KowaiInternet") end)'
  Completed = 'rawset(_G, "BOT_HOLD", 3000); spawn(function() EventManager:AddEvent_1("Ending_Completed") end)'
}
$env:NGO_FAST = "1"; $env:NGO_TOUR = ""; $env:NGO_EVAL = ""; $env:NGO_CONT = ""; $env:NGO_BOOST = ""; $env:NGO_SEED = "3"
$logDir = Join-Path $env:TEMP "ngo_endings"
New-Item -ItemType Directory -Force $logDir | Out-Null
foreach ($k in $cases.Keys) {
  if ($Only -and $Only.Count -gt 0 -and -not ($Only -contains $k)) { continue }
  $env:NGO_INJECT = $cases[$k] + "; return `"$k`""
  $log = Join-Path $logDir "$k.log"
  & $Lua tools\pc_harness.lua . 120000 31 *> $log
  $l = Get-Content $log
  $err = ($l | Select-String "\[error\]").Count
  $end = ($l | Select-String "ENDING DIALOG" | Select-Object -Last 1)
  $diag = ($l | Select-String "\[diag" | Select-Object -Last 1)
  $inj = ($l | Select-String ">> INJECT" | Select-Object -First 1)
  $first = ($l | Select-String "\[error\]" | Select-Object -First 1)
  $res = if ($end) { $end.Line.Trim() } elseif ($diag) { "NO DIALOG | " + $diag.Line.Trim().Substring(0, [Math]::Min(140, $diag.Line.Trim().Length)) } else { "NO DIALOG" }
  "{0,-10} errors={1,-3} {2}{3}" -f $k, $err, $res, $(if ($inj -and $inj.Line -notmatch "\t$k$") { "  [inject: " + $inj.Line.Trim() + "]" } else { "" })
  if ($first) { "    first error: " + $first.Line.Trim().Substring(0, [Math]::Min(200, $first.Line.Trim().Length)) }
}
$env:NGO_INJECT = ""
