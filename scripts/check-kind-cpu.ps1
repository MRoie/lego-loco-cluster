$ErrorActionPreference = 'Continue'
$proc = Get-Process -Id 1652 -ErrorAction SilentlyContinue
if ($proc) {
  $cpu1 = $proc.CPU
  Write-Host "kind.exe CPU time (sample 1): $cpu1"
  Start-Sleep -Seconds 5
  $proc.Refresh()
  $cpu2 = $proc.CPU
  Write-Host "kind.exe CPU time (sample 2, +5s): $cpu2"
  Write-Host "Delta: $($cpu2 - $cpu1) seconds of CPU used in 5 wall-clock seconds"
} else {
  Write-Host "kind.exe (PID 1652) no longer exists"
}

Write-Host "=== docker.exe processes (the actual save/import worker) ===" -ForegroundColor Cyan
Get-CimInstance Win32_Process | Where-Object { $_.Name -eq "docker.exe" } | Select-Object ProcessId, CommandLine

Write-Host "=== DONE ===" -ForegroundColor Green
