$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
$BinDir = Join-Path $RepoRoot ".bin"
$env:PATH = "$BinDir;$env:PATH"
$env:KUBECONFIG = Join-Path $RepoRoot ".kube-config"
Set-Location $RepoRoot

Write-Host "=== All pods in loco namespace ===" -ForegroundColor Cyan
& "$BinDir\kubectl.exe" get pods -n loco -o wide

Write-Host "=== StatefulSet status ===" -ForegroundColor Cyan
& "$BinDir\kubectl.exe" get statefulset -n loco

Write-Host "=== Describe emulator-0 ===" -ForegroundColor Cyan
& "$BinDir\kubectl.exe" describe pod loco-loco-emulator-0 -n loco

Write-Host "=== Recent events ===" -ForegroundColor Cyan
& "$BinDir\kubectl.exe" get events -n loco --sort-by='.lastTimestamp' | Select-Object -Last 40

Write-Host "=== Deployments ===" -ForegroundColor Cyan
& "$BinDir\kubectl.exe" get deployment -n loco

Write-Host "=== DONE ===" -ForegroundColor Green
