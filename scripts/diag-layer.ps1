$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
$BinDir = Join-Path $RepoRoot ".bin"
$env:PATH = "$BinDir;$env:PATH"
Set-Location $RepoRoot

Write-Host "=== Kill any stuck docker CLI processes ===" -ForegroundColor Cyan
Get-Process docker -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

Write-Host "=== docker ps -a ===" -ForegroundColor Cyan
docker ps -a

Write-Host "=== Test reading the big builtin qcow2 file INSIDE a container (no export needed) ===" -ForegroundColor Cyan
docker run --rm --entrypoint sh ghcr.io/mroie/lego-loco-cluster/win98-softgpu:latest -c "ls -la /opt/builtin-images/ && echo '--- reading full file to /dev/null ---' && time cat /opt/builtin-images/win98.qcow2.builtin > /dev/null && echo 'READ OK'"
Write-Host "base image read test exit code: $LASTEXITCODE"

Write-Host "=== Same test on the lan-test patched image ===" -ForegroundColor Cyan
docker run --rm --entrypoint sh lego-loco-emulator:lan-test -c "ls -la /opt/builtin-images/ && echo '--- reading full file to /dev/null ---' && time cat /opt/builtin-images/win98.qcow2.builtin > /dev/null && echo 'READ OK'"
Write-Host "lan-test image read test exit code: $LASTEXITCODE"

Write-Host "=== DONE ===" -ForegroundColor Green
