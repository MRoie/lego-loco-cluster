$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
$BinDir = Join-Path $RepoRoot ".bin"
$env:PATH = "$BinDir;$env:PATH"
$env:KUBECONFIG = Join-Path $RepoRoot ".kube-config"
Set-Location $RepoRoot
$Kube = "$BinDir\kubectl.exe"
New-Item -ItemType Directory -Force -Path "scripts\out" | Out-Null

Write-Host "=== screendumps of both guests ==="
foreach ($i in 0,1) {
  & $Kube exec "loco-loco-emulator-$i" -n loco -- python3 /usr/local/bin/qmp-control.py screendump "/tmp/v$i.ppm" 2>&1 | Out-Null
  & $Kube cp -n loco "loco-loco-emulator-${i}:tmp/v$i.ppm" "scripts/out/vpost$i.ppm" 2>&1 | Out-Null
  Write-Host "dumped vpost$i"
}

Write-Host "=== DHCP leases in instance-0 log ==="
& $Kube logs loco-loco-emulator-0 -n loco --tail=500 2>&1 | Select-String -Pattern "DHCP (OFFER|ACK)" | Select-Object -Last 6

Write-Host "=== ARP + cross-pod TCP (do guests answer on the network now?) ==="
& $Kube exec loco-loco-emulator-0 -n loco -- sh -c "ip neigh flush dev loco-br; nc -z -v -w3 192.168.10.10 139 2>&1; nc -z -v -w3 192.168.10.11 139 2>&1; ip neigh show dev loco-br" 2>&1
& $Kube exec loco-loco-emulator-1 -n loco -- sh -c "nc -z -v -w3 192.168.10.10 139 2>&1; ip neigh show dev loco-br" 2>&1

Write-Host "=== bridge learned guest MACs ==="
& $Kube exec loco-loco-emulator-0 -n loco -- sh -c "bridge fdb show br loco-br | grep -i 52:54 || echo none" 2>&1
Write-Host "=== DONE ==="
