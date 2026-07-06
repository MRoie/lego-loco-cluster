$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
Set-Location $RepoRoot
Write-Host "PWD = $(Get-Location)"
Write-Host "=== stray docker builds / buildx ==="
docker ps --format "{{.Names}} {{.Image}} {{.Status}}" 2>&1 | Select-Object -First 10
Write-Host "=== backend dir has server.js? ==="
Get-ChildItem "$RepoRoot\backend" -Name | Select-Object -First 12
Write-Host "=== BUILD backend classic builder, context=repo root ==="
$env:DOCKER_BUILDKIT = "0"
docker build -f backend/Dockerfile --target production -t ghcr.io/mroie/lego-loco-cluster/backend:test . 2>&1 | Select-Object -Last 12
Write-Host "exit: $LASTEXITCODE"
Write-Host "=== DONE ==="
