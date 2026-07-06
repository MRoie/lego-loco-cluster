$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
$BinDir = Join-Path $RepoRoot ".bin"
$env:PATH = "$BinDir;$env:PATH"
Set-Location $RepoRoot

Write-Host "=== Removing older win98-softgpu tags we no longer need for the LAN test ===" -ForegroundColor Cyan
docker rmi -f "ghcr.io/mroie/lego-loco-cluster/win98-softgpu:win98-rebuild-20260703"
docker rmi -f "ghcr.io/mroie/lego-loco-cluster/win98-softgpu:3dca1f1fd98a86528c2140ae3d484e959244ed5b"

Write-Host "=== Build cache prune ===" -ForegroundColor Cyan
docker builder prune -f

Write-Host "=== docker system df ===" -ForegroundColor Cyan
docker system df

Write-Host "=== Disk free ===" -ForegroundColor Cyan
Get-PSDrive C | Select-Object Used,Free

Write-Host "=== docker images ===" -ForegroundColor Cyan
docker images

Write-Host "=== DONE ===" -ForegroundColor Green
