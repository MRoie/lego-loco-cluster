$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
$BinDir = Join-Path $RepoRoot ".bin"
Remove-Item Env:\KUBECONFIG -ErrorAction SilentlyContinue
Set-Location $RepoRoot
$Kube = "$BinDir\kubectl.exe"
$Pod = "loco-loco-emulator-0"

Write-Host "=== current time in pod vs host ==="
& $Kube exec $Pod -n loco -- date 2>&1
Get-Date

Write-Host "=== nc -z guest 139 (NetBIOS, per runbook: refused=good/network-fine, timeout=bad/no-path) ==="
& $Kube exec $Pod -n loco -- sh -c "nc -zv -w 3 192.168.10.10 139 2>&1" 2>&1

Write-Host "=== nc -z guest 137 (NetBIOS name service, UDP would differ but try tcp anyway) ==="
& $Kube exec $Pod -n loco -- sh -c "nc -zv -w 3 192.168.10.10 445 2>&1" 2>&1

Write-Host "=== arp table (proc/net/arp) - shows if kernel has a resolved entry for guest ip ==="
& $Kube exec $Pod -n loco -- sh -c "cat /proc/net/arp 2>&1" 2>&1

Write-Host "=== bridge fdb again (dynamic vs permanent tells us if traffic is live) ==="
& $Kube exec $Pod -n loco -- sh -c "bridge fdb show br loco-br 2>&1" 2>&1

Write-Host "=== fresh screendump ==="
New-Item -ItemType Directory -Force -Path "scripts\out" | Out-Null
& $Kube exec $Pod -n loco -- python3 /usr/local/bin/qmp-control.py screendump /tmp/postboot.ppm 2>&1
& $Kube cp -n loco "${Pod}:tmp/postboot.ppm" "scripts/out/postboot.ppm" 2>&1

Write-Host "=== DONE ==="
