$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
$BinDir = Join-Path $RepoRoot ".bin"
$env:PATH = "$BinDir;$env:PATH"
$env:KUBECONFIG = Join-Path $RepoRoot ".kube-config"
Set-Location $RepoRoot

Write-Host "=== pods ===" -ForegroundColor Cyan
& "$BinDir\kubectl.exe" get pods -n loco -o wide

Write-Host "=== emulator-1 describe (events tail) ===" -ForegroundColor Cyan
& "$BinDir\kubectl.exe" describe pod loco-loco-emulator-1 -n loco | Select-Object -Last 40

Write-Host "=== emulator-1 previous logs (if crashed) ===" -ForegroundColor Cyan
& "$BinDir\kubectl.exe" logs loco-loco-emulator-1 -n loco --previous --tail=80

Write-Host "=== emulator-1 current logs (tail) ===" -ForegroundColor Cyan
& "$BinDir\kubectl.exe" logs loco-loco-emulator-1 -n loco --tail=80

Write-Host "=== DONE ===" -ForegroundColor Green
