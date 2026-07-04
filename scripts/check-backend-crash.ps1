$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
$BinDir = Join-Path $RepoRoot ".bin"
$env:PATH = "$BinDir;$env:PATH"
$env:KUBECONFIG = Join-Path $RepoRoot ".kube-config"
Set-Location $RepoRoot

Write-Host "=== backend describe (events) ===" -ForegroundColor Cyan
& "$BinDir\kubectl.exe" describe pod loco-loco-backend-6d5c978668-s7nh4 -n loco | Select-Object -Last 40

Write-Host "=== backend previous logs (crash tail) ===" -ForegroundColor Cyan
& "$BinDir\kubectl.exe" logs loco-loco-backend-6d5c978668-s7nh4 -n loco --previous --tail=60

Write-Host "=== DONE ===" -ForegroundColor Green
