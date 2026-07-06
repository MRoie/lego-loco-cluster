$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
$BinDir = Join-Path $RepoRoot ".bin"
$env:PATH = "$BinDir;$env:PATH"
$env:KUBECONFIG = Join-Path $RepoRoot ".kube-config"
Set-Location $RepoRoot

Write-Host "=== LOCAL test: instance-0 pod -> its OWN guest 192.168.10.10:2300 ===" -ForegroundColor Cyan
& "$BinDir\kubectl.exe" exec loco-loco-emulator-0 -n loco -- sh -c "nc -z -v -w3 192.168.10.10 2300" 2>&1

Write-Host "=== LOCAL test: instance-1 pod -> its OWN guest 192.168.10.11:2300 ===" -ForegroundColor Cyan
& "$BinDir\kubectl.exe" exec loco-loco-emulator-1 -n loco -- sh -c "nc -z -v -w3 192.168.10.11 2300" 2>&1

Write-Host "=== instance-0 bridge fdb (vxlan0) ===" -ForegroundColor Cyan
& "$BinDir\kubectl.exe" exec loco-loco-emulator-0 -n loco -- sh -c "bridge fdb show dev vxlan0 2>&1 || ip -d link show vxlan0" 2>&1

Write-Host "=== instance-1 bridge fdb (vxlan0) ===" -ForegroundColor Cyan
& "$BinDir\kubectl.exe" exec loco-loco-emulator-1 -n loco -- sh -c "bridge fdb show dev vxlan0 2>&1 || ip -d link show vxlan0" 2>&1

Write-Host "=== instance-0 arp table ===" -ForegroundColor Cyan
& "$BinDir\kubectl.exe" exec loco-loco-emulator-0 -n loco -- sh -c "ip neigh show" 2>&1

Write-Host "=== instance-1 arp table ===" -ForegroundColor Cyan
& "$BinDir\kubectl.exe" exec loco-loco-emulator-1 -n loco -- sh -c "ip neigh show" 2>&1

Write-Host "=== instance-1 addr/bridge state ===" -ForegroundColor Cyan
& "$BinDir\kubectl.exe" exec loco-loco-emulator-1 -n loco -- ip addr show 2>&1

Write-Host "=== try arping instance-0 guest from instance-1 pod (if arping exists) ===" -ForegroundColor Cyan
& "$BinDir\kubectl.exe" exec loco-loco-emulator-1 -n loco -- sh -c "which arping && arping -c 3 -I loco-br 192.168.10.10 || echo no-arping" 2>&1

Write-Host "=== DONE ===" -ForegroundColor Green
