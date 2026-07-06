$ErrorActionPreference = 'Continue'

Write-Host "=== Stopping Docker Desktop process (if running) ===" -ForegroundColor Cyan
Get-Process "Docker Desktop" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3

Write-Host "=== wsl --shutdown (force-terminate all WSL2 VMs incl. docker-desktop) ===" -ForegroundColor Cyan
wsl --shutdown
Write-Host "wsl --shutdown exit code: $LASTEXITCODE"

Write-Host "=== wsl -l -v (list distros/state) ===" -ForegroundColor Cyan
wsl -l -v

Start-Sleep -Seconds 5

Write-Host "=== Relaunching Docker Desktop ===" -ForegroundColor Cyan
$dockerExe = "C:\Program Files\Docker\Docker\Docker Desktop.exe"
if (Test-Path $dockerExe) {
  Start-Process $dockerExe
  Write-Host "Launched: $dockerExe"
} else {
  Write-Host "Docker Desktop.exe not found at expected path, trying Start-Process by name" -ForegroundColor Yellow
  Start-Process "Docker Desktop"
}

Write-Host "=== DONE (Docker Desktop launching in background, will take 1-2 min to be ready) ===" -ForegroundColor Green
