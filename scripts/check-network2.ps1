$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
$BinDir = Join-Path $RepoRoot ".bin"
$env:PATH = "$BinDir;$env:PATH"
$env:KUBECONFIG = Join-Path $RepoRoot ".kube-config"
Set-Location $RepoRoot

Write-Host "=== emulator-0 FULL log ===" -ForegroundColor Cyan
& "$BinDir\kubectl.exe" logs loco-loco-emulator-0 -n loco

Write-Host "=== emulator-1 FULL log ===" -ForegroundColor Cyan
& "$BinDir\kubectl.exe" logs loco-loco-emulator-1 -n loco

Write-Host "=== DONE ===" -ForegroundColor Green
