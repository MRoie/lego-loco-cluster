$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
$BinDir = Join-Path $RepoRoot ".bin"
$env:PATH = "$BinDir;$env:PATH"
$env:KUBECONFIG = Join-Path $RepoRoot ".kube-config"
Set-Location $RepoRoot

Write-Host "=== Building network-patched emulator image (local tag) ===" -ForegroundColor Cyan
docker build -f containers/qemu-softgpu/Dockerfile.patch-network -t lego-loco-emulator:lan-test containers/qemu-softgpu
$buildExit = $LASTEXITCODE
Write-Host "Build exit code: $buildExit"

if ($buildExit -eq 0) {
  Write-Host "=== Verifying VXLAN code present in patched image ===" -ForegroundColor Cyan
  docker run --rm lego-loco-emulator:lan-test grep -c "VXLAN\|ENABLE_GUEST_L2_MESH" /entrypoint.sh

  Write-Host "=== Loading into kind ===" -ForegroundColor Cyan
  & "$BinDir\kind.exe" load docker-image lego-loco-emulator:lan-test --name loco
} else {
  Write-Host "Build failed" -ForegroundColor Red
}

Write-Host "=== DONE ===" -ForegroundColor Green
