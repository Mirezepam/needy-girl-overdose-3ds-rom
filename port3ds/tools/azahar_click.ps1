# Clicks inside the Azahar window at window-relative coordinates (to drive the emulated touch screen).
# usage: powershell -File azahar_click.ps1 <x> <y> [holdMs]
param([int]$X, [int]$Y, [int]$Hold = 80)
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class W {
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, IntPtr e);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
}
"@
$p = Get-Process azahar | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
[W]::SetForegroundWindow($p.MainWindowHandle) | Out-Null
$r = New-Object W+RECT
[W]::GetWindowRect($p.MainWindowHandle, [ref]$r) | Out-Null
[W]::SetCursorPos($r.Left + $X, $r.Top + $Y) | Out-Null
Start-Sleep -Milliseconds 50
[W]::mouse_event(0x02, 0, 0, 0, [IntPtr]::Zero)
Start-Sleep -Milliseconds $Hold
[W]::mouse_event(0x04, 0, 0, 0, [IntPtr]::Zero)
