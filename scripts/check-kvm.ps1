$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
$BinDir = Join-Path $RepoRoot ".bin"
$env:PATH = "$BinDir;$env:PATH"
$env:KUBECONFIG = Join-Path $RepoRoot ".kube-config"
Set-Location $RepoRoot

Write-Host "=== /dev/kvm on kind node (loco-control-plane container) ===" -ForegroundColor Cyan
docker exec loco-control-plane ls -la /dev/kvm 2>&1

Write-Host "=== /dev/kvm inside emulator-0 pod (currently, kvm disabled) ===" -ForegroundColor Cyan
& "$BinDir\kubectl.exe" exec -n loco loco-loco-emulator-0 -- ls -la /dev/kvm 2>&1

Write-Host "=== CPU virtualization flags on Docker Desktop VM (via kind node) ===" -ForegroundColor Cyan
docker exec loco-control-plane sh -c "grep -Eo 'vmx|svm' /proc/cpuinfo | sort -u" 2>&1

Write-Host "=== kernel modules (kvm) on Docker Desktop VM ===" -ForegroundColor Cyan
docker exec loco-control-plane sh -c "lsmod 2>/dev/null | grep -i kvm; cat /proc/modules 2>/dev/null | grep -i kvm" 2>&1

Write-Host "=== DONE ===" -ForegroundColor Green
