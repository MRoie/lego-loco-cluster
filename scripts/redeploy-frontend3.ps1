$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
$BinDir = Join-Path $RepoRoot ".bin"
$env:PATH = "$BinDir;$env:PATH"
$env:KUBECONFIG = Join-Path $RepoRoot ".kube-config"

Set-Location $RepoRoot

Write-Host "=== Rebuilding frontend image (novnc override pin to 1.6.0) ===" -ForegroundColor Cyan
docker build -f frontend/Dockerfile --target production -t lego-loco-frontend:local ./frontend
$buildExit = $LASTEXITCODE
Write-Host "Build exit code: $buildExit"

if ($buildExit -eq 0) {
  Write-Host "=== Loading frontend image into kind ===" -ForegroundColor Cyan
  & "$BinDir\kind.exe" load docker-image lego-loco-frontend:local --name loco

  Write-Host "=== Restarting frontend deployment ===" -ForegroundColor Cyan
  & "$BinDir\kubectl.exe" rollout restart deployment/loco-loco-frontend -n loco
} else {
  Write-Host "Build failed, skipping load/restart" -ForegroundColor Red
}

Write-Host "=== Waiting 25s then checking pod status ===" -ForegroundColor Cyan
Start-Sleep -Seconds 25
& "$BinDir\kubectl.exe" get pods -n loco -o wide

Write-Host "=== DONE ===" -ForegroundColor Green
