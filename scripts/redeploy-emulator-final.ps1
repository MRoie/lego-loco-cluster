$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
$BinDir = Join-Path $RepoRoot ".bin"
$env:PATH = "$BinDir;$env:PATH"
$env:KUBECONFIG = Join-Path $RepoRoot ".kube-config"
Set-Location $RepoRoot

Write-Host "=== Helm upgrade with network-patched emulator image ===" -ForegroundColor Cyan
& "$BinDir\helm.exe" upgrade --install loco helm/loco-chart -n loco -f helm/loco-chart/values-lan-test.yaml --timeout 5m

Write-Host "=== Scaling VR deployment to 0 (chart gap workaround) ===" -ForegroundColor Cyan
& "$BinDir\kubectl.exe" scale deployment/loco-loco-vr -n loco --replicas=0

Write-Host "=== Force-deleting emulator pods to pick up new image ===" -ForegroundColor Cyan
& "$BinDir\kubectl.exe" delete pod loco-loco-emulator-0 -n loco --force --grace-period=0 2>&1 | Out-Null
& "$BinDir\kubectl.exe" delete pod loco-loco-emulator-1 -n loco --force --grace-period=0 2>&1 | Out-Null

Write-Host "=== Waiting 40s ===" -ForegroundColor Cyan
Start-Sleep -Seconds 40

Write-Host "=== Pods ===" -ForegroundColor Cyan
& "$BinDir\kubectl.exe" get pods -n loco -o wide

Write-Host "=== DONE ===" -ForegroundColor Green
