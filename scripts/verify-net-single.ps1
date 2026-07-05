$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
$BinDir = Join-Path $RepoRoot ".bin"
Remove-Item Env:\KUBECONFIG -ErrorAction SilentlyContinue
Set-Location $RepoRoot
$Kube = "$BinDir\kubectl.exe"
$Pod = "loco-loco-emulator-0"

Write-Host "=== DHCP server / entrypoint logs (ACK for guest?) ==="
& $Kube logs $Pod -n loco --tail=100 2>&1 | Select-String -Pattern "DHCP|ACK|dhcp|mini_dhcp|bound|lease"

Write-Host "=== bridge loco-br fdb (guest MAC learned on tap?) ==="
& $Kube exec $Pod -n loco -- sh -c "bridge fdb show br loco-br 2>&1" 2>&1

Write-Host "=== ip neigh on loco-br (does guest answer ARP for its own IP?) ==="
& $Kube exec $Pod -n loco -- sh -c "ip neigh show dev loco-br 2>&1" 2>&1

Write-Host "=== ip addr on loco-br / tap0 ==="
& $Kube exec $Pod -n loco -- sh -c "ip addr show loco-br 2>&1; ip addr show tap0 2>&1" 2>&1

Write-Host "=== active-ping the expected guest IP from inside the pod netns ==="
& $Kube exec $Pod -n loco -- sh -c "ping -c 3 -W 2 192.168.10.10 2>&1" 2>&1

Write-Host "=== DONE ==="
