# Restarts Azahar with the port, parked off-screen without taking focus (for unattended tests).
# usage: powershell -File azahar_run_cia.ps1 <installed .app>  (install first: azahar.exe -i needy3ds.cia)
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class W3 {
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int cx, int cy, uint f);
}
"@
Get-Process azahar -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 500
Start-Process "C:\Program Files\Azahar\azahar.exe" -ArgumentList ('"' + $args[0] + '"')
for ($i = 0; $i -lt 50; $i++) {
  Start-Sleep -Milliseconds 200
  $p = Get-Process azahar -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
  if ($p) { break }
}
[W3]::ShowWindow($p.MainWindowHandle, 4) | Out-Null          # SW_SHOWNOACTIVATE
[W3]::SetWindowPos($p.MainWindowHandle, [IntPtr]::Zero, -2400, 50, 1100, 760, 0x0014) | Out-Null  # NOZORDER|NOACTIVATE
Write-Output "azahar running off-screen"
