$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
$BinDir = Join-Path $RepoRoot ".bin"
$env:PATH = "$BinDir;$env:PATH"
Set-Location $RepoRoot

Write-Host "=== Test reading base image builtin qcow2 fully (md5sum) ===" -ForegroundColor Cyan
docker run --rm --entrypoint sh ghcr.io/mroie/lego-loco-cluster/win98-softgpu:latest -c "md5sum /opt/builtin-images/win98.qcow2.builtin && echo BASE_READ_OK"
Write-Host "base image exit code: $LASTEXITCODE"

Write-Host "=== Test reading lan-test image builtin qcow2 fully (md5sum) ===" -ForegroundColor Cyan
docker run --rm --entrypoint sh lego-loco-emulator:lan-test -c "md5sum /opt/builtin-images/win98.qcow2.builtin && echo LANTEST_READ_OK"
Write-Host "lan-test image exit code: $LASTEXITCODE"

Write-Host "=== DONE ===" -ForegroundColor Green
