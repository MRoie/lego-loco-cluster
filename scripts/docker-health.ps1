$ErrorActionPreference = 'Continue'
Write-Host "=== docker info ===" -ForegroundColor Cyan
docker info
Write-Host "docker info exit code: $LASTEXITCODE"
Write-Host "=== docker version ===" -ForegroundColor Cyan
docker version
Write-Host "=== DONE ===" -ForegroundColor Green
