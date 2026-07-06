$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
$BinDir = Join-Path $RepoRoot ".bin"
$env:PATH = "$BinDir;$env:PATH"
$env:KUBECONFIG = Join-Path $RepoRoot ".kube-config"
Set-Location $RepoRoot

Write-Host "=== Services ===" -ForegroundColor Cyan
& "$BinDir\kubectl.exe" get svc -n loco

Write-Host "=== emulator-0 entrypoint log (last 80 lines) ===" -ForegroundColor Cyan
& "$BinDir\kubectl.exe" logs loco-loco-emulator-0 -n loco --tail=80

Write-Host "=== emulator-1 entrypoint log (last 80 lines) ===" -ForegroundColor Cyan
& "$BinDir\kubectl.exe" logs loco-loco-emulator-1 -n loco --tail=80

Write-Host "=== DONE ===" -ForegroundColor Green
