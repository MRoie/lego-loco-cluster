$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
$BinDir = Join-Path $RepoRoot ".bin"
$env:PATH = "$BinDir;$env:PATH"
$env:KUBECONFIG = Join-Path $RepoRoot ".kube-config"
Set-Location $RepoRoot

Write-Host "=== Image digest running in pod ===" -ForegroundColor Cyan
& "$BinDir\kubectl.exe" get pod loco-loco-emulator-0 -n loco -o jsonpath="{.status.containerStatuses[0].imageID}"
Write-Host ""

Write-Host "=== grep VXLAN in container entrypoint.sh ===" -ForegroundColor Cyan
& "$BinDir\kubectl.exe" exec loco-loco-emulator-0 -n loco -- grep -n "VXLAN\|ENABLE_GUEST_L2_MESH\|setup_guest_l2_mesh\|start_guest_dhcp\|mini_dhcp" /entrypoint.sh

Write-Host "=== entrypoint.sh line count in container ===" -ForegroundColor Cyan
& "$BinDir\kubectl.exe" exec loco-loco-emulator-0 -n loco -- wc -l /entrypoint.sh

Write-Host "=== ip link show (check for vxlan interface) ===" -ForegroundColor Cyan
& "$BinDir\kubectl.exe" exec loco-loco-emulator-0 -n loco -- ip link show

Write-Host "=== ps aux in emulator-0 (look for dhcp/mesh reconciler) ===" -ForegroundColor Cyan
& "$BinDir\kubectl.exe" exec loco-loco-emulator-0 -n loco -- ps aux

Write-Host "=== DONE ===" -ForegroundColor Green
