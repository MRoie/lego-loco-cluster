$ErrorActionPreference = 'Continue'
Write-Host "=== wsl version/status ==="
wsl --status 2>&1
Write-Host "=== wsl distros (-l -v) ==="
wsl -l -v 2>&1
Write-Host "=== docker desktop exe ==="
$paths = @(
  "$env:ProgramFiles\Docker\Docker\Docker Desktop.exe",
  "${env:ProgramFiles(x86)}\Docker\Docker\Docker Desktop.exe"
)
foreach ($p in $paths) { if (Test-Path $p) { Write-Host "FOUND: $p" } }
Write-Host "=== docker desktop process ==="
Get-Process "Docker Desktop" -ErrorAction SilentlyContinue | Select-Object Id,ProcessName
Write-Host "=== DONE ==="
