$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
$BinDir = Join-Path $RepoRoot ".bin"
$env:PATH = "$BinDir;$env:PATH"
$env:KUBECONFIG = Join-Path $RepoRoot ".kube-config"

Set-Location $RepoRoot

Write-Host "=== Building backend image ===" -ForegroundColor Cyan
docker build -f backend/Dockerfile --target production -t lego-loco-backend:local .

Write-Host "=== Building frontend image ===" -ForegroundColor Cyan
docker build -f frontend/Dockerfile --target production -t lego-loco-frontend:local ./frontend

Write-Host "=== Loading images into kind cluster ===" -ForegroundColor Cyan
& "$BinDir\kind.exe" load docker-image lego-loco-backend:local --name loco
& "$BinDir\kind.exe" load docker-image lego-loco-frontend:local --name loco

Write-Host "=== Pulling emulator image on host (to verify it is reachable) ===" -ForegroundColor Cyan
docker pull ghcr.io/mroie/lego-loco-cluster/win98-softgpu:latest

Write-Host "=== Creating namespace ===" -ForegroundColor Cyan
& "$BinDir\kubectl.exe" create namespace loco --dry-run=client -o yaml | & "$BinDir\kubectl.exe" apply -f -

Write-Host "=== Helm lint / template check ===" -ForegroundColor Cyan
& "$BinDir\helm.exe" template loco helm/loco-chart -n loco -f helm/loco-chart/values-lan-test.yaml > "$RepoRoot\scripts\rendered-manifests.yaml"
Write-Host "Rendered manifest exit code: $LASTEXITCODE"

Write-Host "=== Helm install/upgrade ===" -ForegroundColor Cyan
& "$BinDir\helm.exe" upgrade --install loco helm/loco-chart -n loco -f helm/loco-chart/values-lan-test.yaml --timeout 5m

Write-Host "=== Waiting a moment for resources to be created ===" -ForegroundColor Cyan
Start-Sleep -Seconds 5

Write-Host "=== Pod status ===" -ForegroundColor Cyan
& "$BinDir\kubectl.exe" get pods -n loco -o wide

Write-Host "=== DONE ===" -ForegroundColor Green
