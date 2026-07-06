$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
$BinDir = Join-Path $RepoRoot ".bin"
$env:PATH = "$BinDir;$env:PATH"
$env:KUBECONFIG = Join-Path $RepoRoot ".kube-config"
Set-Location $RepoRoot

Write-Host "=== Pods ===" -ForegroundColor Cyan
& "$BinDir\kubectl.exe" get pods -n loco -o wide

Write-Host "=== StatefulSet ===" -ForegroundColor Cyan
& "$BinDir\kubectl.exe" get statefulset -n loco

Write-Host "=== emulator-0 tail ===" -ForegroundColor Cyan
& "$BinDir\kubectl.exe" logs loco-loco-emulator-0 -n loco --tail=30

Write-Host "=== emulator-1 tail (if exists) ===" -ForegroundColor Cyan
& "$BinDir\kubectl.exe" logs loco-loco-emulator-1 -n loco --tail=30

Write-Host "=== DONE ===" -ForegroundColor Green
