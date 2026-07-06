$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
$BinDir = Join-Path $RepoRoot ".bin"
$env:PATH = "$BinDir;$env:PATH"
$env:KUBECONFIG = Join-Path $RepoRoot ".kube-config"

Set-Location $RepoRoot

Write-Host "=== Rebuilding frontend image (novnc import fix) ===" -ForegroundColor Cyan
docker build -f frontend/Dockerfile --target production -t lego-loco-frontend:local ./frontend

Write-Host "=== Loading frontend image into kind ===" -ForegroundColor Cyan
& "$BinDir\kind.exe" load docker-image lego-loco-frontend:local --name loco

Write-Host "=== Helm upgrade ===" -ForegroundColor Cyan
& "$BinDir\helm.exe" upgrade --install loco helm/loco-chart -n loco -f helm/loco-chart/values-lan-test.yaml --timeout 5m

Write-Host "=== Restarting frontend deployment to pick up new image ===" -ForegroundColor Cyan
& "$BinDir\kubectl.exe" rollout restart deployment/loco-loco-frontend -n loco
& "$BinDir\kubectl.exe" rollout restart statefulset/loco-loco-emulator -n loco

Write-Host "=== Scaling down VR deployment (not needed for this test) ===" -ForegroundColor Cyan
& "$BinDir\kubectl.exe" scale deployment/loco-loco-vr -n loco --replicas=0

Write-Host "=== Waiting 20s then checking pod status ===" -ForegroundColor Cyan
Start-Sleep -Seconds 20
& "$BinDir\kubectl.exe" get pods -n loco -o wide

Write-Host "=== DONE ===" -ForegroundColor Green
