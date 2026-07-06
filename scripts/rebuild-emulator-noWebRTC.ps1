$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
$BinDir = Join-Path $RepoRoot ".bin"
$env:PATH = "$BinDir;$env:PATH"
$env:KUBECONFIG = Join-Path $RepoRoot ".kube-config"
Set-Location $RepoRoot

Write-Host "=== Verify base image present locally ===" -ForegroundColor Cyan
docker images qemu-loco-softgpu

Write-Host "=== Building lightweight patch layer (entrypoint.sh only, no QEMU recompile) ===" -ForegroundColor Cyan
docker build -f containers/qemu-softgpu/Dockerfile.patch-network `
  --build-arg BASE_IMAGE=qemu-loco-softgpu:v28-qemu3dfx `
  -t qemu-loco-softgpu:v28-qemu3dfx `
  containers/qemu-softgpu
$buildExit = $LASTEXITCODE
Write-Host "Build exit code: $buildExit"

if ($buildExit -eq 0) {
  Write-Host "=== Loading into kind ===" -ForegroundColor Cyan
  & "$BinDir\kind.exe" load docker-image qemu-loco-softgpu:v28-qemu3dfx --name loco

  Write-Host "=== Restarting emulator statefulset (both instances) ===" -ForegroundColor Cyan
  & "$BinDir\kubectl.exe" rollout restart statefulset/loco-loco-emulator -n loco
} else {
  Write-Host "Build failed, skipping load/restart" -ForegroundColor Red
}

Write-Host "=== Waiting 45s then checking pod status ===" -ForegroundColor Cyan
Start-Sleep -Seconds 45
& "$BinDir\kubectl.exe" get pods -n loco -o wide

Write-Host "=== DONE ===" -ForegroundColor Green
