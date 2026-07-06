$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
$BinDir = Join-Path $RepoRoot ".bin"
$env:PATH = "$BinDir;$env:PATH"
Write-Host "=== kind.exe process still running? ===" -ForegroundColor Cyan
Get-CimInstance Win32_Process | Where-Object { $_.Name -like "kind*" } | Select-Object ProcessId, CommandLine

Write-Host "=== image present in kind node containerd? ===" -ForegroundColor Cyan
docker exec loco-control-plane crictl images 2>&1 | Select-String "lego-loco-emulator"

Write-Host "=== DONE ===" -ForegroundColor Green
