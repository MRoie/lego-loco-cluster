$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
Set-Location $RepoRoot
$date = Get-Date -Format "yyyyMMdd"
$repo = "ghcr.io/mroie/lego-loco-cluster"

Write-Host "RepoRoot = $RepoRoot"
Write-Host "PWD = $(Get-Location)"
Write-Host "backend dir listing:"
Get-ChildItem "$RepoRoot\backend" -Name | Select-Object -First 8

Write-Host "=== BUILD backend (explicit context, classic builder) ==="
$env:DOCKER_BUILDKIT = "0"
docker build -f "$RepoRoot\backend\Dockerfile" --target production -t "${repo}/backend:$date" -t "${repo}/backend:latest" "$RepoRoot" 2>&1 | Select-Object -Last 8
Write-Host "backend build exit: $LASTEXITCODE"

Write-Host "=== BUILD frontend ==="
docker build -f "$RepoRoot\frontend\Dockerfile" --target production -t "${repo}/frontend:$date" -t "${repo}/frontend:latest" "$RepoRoot\frontend" 2>&1 | Select-Object -Last 8
Write-Host "frontend build exit: $LASTEXITCODE"

Write-Host "=== PUSH backend ==="
docker push "${repo}/backend:$date" 2>&1 | Select-Object -Last 2
docker push "${repo}/backend:latest" 2>&1 | Select-Object -Last 2
Write-Host "=== PUSH frontend ==="
docker push "${repo}/frontend:$date" 2>&1 | Select-Object -Last 2
docker push "${repo}/frontend:latest" 2>&1 | Select-Object -Last 2

Write-Host "=== images ==="
docker images 2>&1 | Select-String "lego-loco-cluster"
Write-Host "=== DONE ==="
