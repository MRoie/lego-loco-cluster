$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
$BinDir = Join-Path $RepoRoot ".bin"
$env:PATH = "$BinDir;$env:PATH"
Set-Location $RepoRoot

Write-Host "=== docker images (all) ===" -ForegroundColor Cyan
docker images

Write-Host "=== DONE ===" -ForegroundColor Green
