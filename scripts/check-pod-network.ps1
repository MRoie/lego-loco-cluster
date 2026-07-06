$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
$BinDir = Join-Path $RepoRoot ".bin"
$env:PATH = "$BinDir;$env:PATH"
$env:KUBECONFIG = Join-Path $RepoRoot ".kube-config"
Set-Location $RepoRoot

Write-Host "=== Pod IPs (pod network, NOT guest IPs) ===" -ForegroundColor Cyan
& "$BinDir\kubectl.exe" get pods -n loco -o wide

Write-Host "=== Ping guest IP 192.168.10.10 (instance-0) from instance-1 pod ===" -ForegroundColor Cyan
& "$BinDir\kubectl.exe" exec loco-loco-emulator-1 -n loco -- ping -c 3 192.168.10.10

Write-Host "=== Ping guest IP 192.168.10.11 (instance-1) from instance-0 pod ===" -ForegroundColor Cyan
& "$BinDir\kubectl.exe" exec loco-loco-emulator-0 -n loco -- ping -c 3 192.168.10.11

Write-Host "=== Check port 2300 / 47624 reachability instance-1 -> instance-0 ===" -ForegroundColor Cyan
& "$BinDir\kubectl.exe" exec loco-loco-emulator-1 -n loco -- sh -c "which nc && nc -z -v -w3 192.168.10.10 2300; nc -z -v -w3 192.168.10.10 47624" 2>&1

Write-Host "=== Bridge / TAP interfaces on instance-0 ===" -ForegroundColor Cyan
& "$BinDir\kubectl.exe" exec loco-loco-emulator-0 -n loco -- ip addr show 2>&1

Write-Host "=== DONE ===" -ForegroundColor Green
