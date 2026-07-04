$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
$BinDir = Join-Path $RepoRoot ".bin"
$env:PATH = "$BinDir;$env:PATH"
$env:KUBECONFIG = Join-Path $RepoRoot ".kube-config"
Set-Location $RepoRoot
$Kube = "$BinDir\kubectl.exe"

Write-Host "=== DHCP server log (instance-0) ==="
& $Kube logs loco-loco-emulator-0 -n loco --tail=400 2>&1 | Select-String -Pattern "DHCP|OFFER|ACK|Sent" | Select-Object -Last 12

Write-Host "=== instance-0: arping guest .10 and .11 from pod ==="
& $Kube exec loco-loco-emulator-0 -n loco -- sh -c "ip neigh flush dev loco-br; nc -z -v -w3 192.168.10.10 139; nc -z -v -w3 192.168.10.11 139; ip neigh show" 2>&1

Write-Host "=== instance-1: reach .10 from pod-1 ==="
& $Kube exec loco-loco-emulator-1 -n loco -- sh -c "nc -z -v -w3 192.168.10.10 139; ip neigh show" 2>&1

Write-Host "=== bridge fdb learned MACs (look for 52:54:00) ==="
& $Kube exec loco-loco-emulator-0 -n loco -- sh -c "bridge fdb show br loco-br | grep -i 52:54 || echo none-0" 2>&1
& $Kube exec loco-loco-emulator-1 -n loco -- sh -c "bridge fdb show br loco-br | grep -i 52:54 || echo none-1" 2>&1
Write-Host "=== DONE ==="
