$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
$BinDir = Join-Path $RepoRoot ".bin"
$env:PATH = "$BinDir;$env:PATH"

Write-Host "=== is perf-rebuild-emulator.ps1 (PID 8572 earlier) still alive? ===" -ForegroundColor Cyan
Get-Process -Id 8572 -ErrorAction SilentlyContinue
Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -like "*perf-rebuild-emulator*" } | Select-Object ProcessId, CommandLine

Write-Host "=== any kind*.exe process (broad) ===" -ForegroundColor Cyan
Get-CimInstance Win32_Process | Where-Object { $_.Name -like "*kind*" } | Select-Object ProcessId, Name, CommandLine

Write-Host "=== docker images | grep lego-loco-emulator ===" -ForegroundColor Cyan
docker images lego-loco-emulator

Write-Host "=== docker exec loco-control-plane ctr -n k8s.io images list (containerd direct) ===" -ForegroundColor Cyan
docker exec loco-control-plane ctr -n k8s.io images list 2>&1 | Select-String "lego-loco-emulator"

Write-Host "=== full perf-rebuild-emulator-result.txt tail ===" -ForegroundColor Cyan
Get-Content "$RepoRoot\scripts\perf-rebuild-emulator-result.txt" -Tail 20

Write-Host "=== DONE ===" -ForegroundColor Green
