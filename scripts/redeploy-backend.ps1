$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
$BinDir = Join-Path $RepoRoot ".bin"
$env:PATH = "$BinDir;$env:PATH"
$env:KUBECONFIG = Join-Path $RepoRoot ".kube-config"

Set-Location $RepoRoot

Write-Host "=== Rebuilding backend image (disable invasive VNC quality probe) ===" -ForegroundColor Cyan
docker build -f backend/Dockerfile --target production -t lego-loco-backend:v15-agents .
$buildExit = $LASTEXITCODE
Write-Host "Build exit code: $buildExit"

if ($buildExit -eq 0) {
  Write-Host "=== Loading backend image into kind ===" -ForegroundColor Cyan
  & "$BinDir\kind.exe" load docker-image lego-loco-backend:v15-agents --name loco

  Write-Host "=== Restarting backend deployment ===" -ForegroundColor Cyan
  & "$BinDir\kubectl.exe" rollout restart deployment/loco-loco-backend -n loco
} else {
  Write-Host "Build failed, skipping load/restart" -ForegroundColor Red
}

Write-Host "=== Waiting 25s then checking pod status ===" -ForegroundColor Cyan
Start-Sleep -Seconds 25
& "$BinDir\kubectl.exe" get pods -n loco -o wide

Write-Host "=== DONE ===" -ForegroundColor Green
