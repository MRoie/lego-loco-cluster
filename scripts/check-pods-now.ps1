$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
$BinDir = Join-Path $RepoRoot ".bin"
$env:PATH = "$BinDir;$env:PATH"
$env:KUBECONFIG = Join-Path $RepoRoot ".kube-config"
Set-Location $RepoRoot

Write-Host "=== Pods ===" -ForegroundColor Cyan
& "$BinDir\kubectl.exe" get pods -n loco -o wide

Write-Host "=== emulator-0 recent logs ===" -ForegroundColor Cyan
& "$BinDir\kubectl.exe" logs statefulset/loco-loco-emulator -n loco --tail=30 -c emulator 2>&1

Write-Host "=== emulator-0 events ===" -ForegroundColor Cyan
& "$BinDir\kubectl.exe" get events -n loco --sort-by=.lastTimestamp | Select-Object -Last 20

Write-Host "=== DONE ===" -ForegroundColor Green
