$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
$BinDir = Join-Path $RepoRoot ".bin"
$env:PATH = "$BinDir;$env:PATH"
$env:KUBECONFIG = Join-Path $RepoRoot ".kube-config"

Set-Location $RepoRoot

Write-Host "=== Verifying source file content (should show core/rfb.js) ===" -ForegroundColor Cyan
Select-String -Path "frontend\src\components\NoVNCViewer.jsx" -Pattern "novnc"
Select-String -Path "frontend\src\components\VRNoVNCViewer.jsx" -Pattern "novnc"

Write-Host "=== Rebuilding frontend image with --no-cache ===" -ForegroundColor Cyan
docker build --no-cache -f frontend/Dockerfile --target production -t lego-loco-frontend:local ./frontend

Write-Host "=== Loading frontend image into kind ===" -ForegroundColor Cyan
& "$BinDir\kind.exe" load docker-image lego-loco-frontend:local --name loco

Write-Host "=== Restarting frontend deployment ===" -ForegroundColor Cyan
& "$BinDir\kubectl.exe" rollout restart deployment/loco-loco-frontend -n loco

Write-Host "=== Waiting 20s then checking pod status ===" -ForegroundColor Cyan
Start-Sleep -Seconds 20
& "$BinDir\kubectl.exe" get pods -n loco -o wide

Write-Host "=== DONE ===" -ForegroundColor Green
