$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
$BinDir = Join-Path $RepoRoot ".bin"
$env:PATH = "$BinDir;$env:PATH"
$env:KUBECONFIG = Join-Path $RepoRoot ".kube-config"
Set-Location $RepoRoot

Write-Host "=== Scaling VR deployment to 0 ===" -ForegroundColor Cyan
& "$BinDir\kubectl.exe" scale deployment/loco-loco-vr -n loco --replicas=0

Write-Host "=== Force-deleting stuck emulator pods to pick up new volume spec ===" -ForegroundColor Cyan
& "$BinDir\kubectl.exe" delete pod loco-loco-emulator-0 -n loco --force --grace-period=0
& "$BinDir\kubectl.exe" delete pod loco-loco-emulator-1 -n loco --force --grace-period=0

Write-Host "=== Waiting 30s ===" -ForegroundColor Cyan
Start-Sleep -Seconds 30

Write-Host "=== Pods ===" -ForegroundColor Cyan
& "$BinDir\kubectl.exe" get pods -n loco -o wide

Write-Host "=== Describe emulator-0 (post-recreate) ===" -ForegroundColor Cyan
& "$BinDir\kubectl.exe" describe pod loco-loco-emulator-0 -n loco | Select-String -Pattern "Events:|Warning|Normal|Mounts:|Volumes:" -Context 0,3

Write-Host "=== DONE ===" -ForegroundColor Green
