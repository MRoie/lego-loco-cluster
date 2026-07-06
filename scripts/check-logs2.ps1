$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
$BinDir = Join-Path $RepoRoot ".bin"
Remove-Item Env:\KUBECONFIG -ErrorAction SilentlyContinue
Set-Location $RepoRoot
$Kube = "$BinDir\kubectl.exe"
$Pod = "loco-loco-emulator-0"

Write-Host "=== full recent log tail (last 150 lines) ==="
& $Kube logs $Pod -n loco --tail=150 2>&1

Write-Host "=== try nc / which binaries available for network test ==="
& $Kube exec $Pod -n loco -- sh -c "which nc ncat busybox arping 2>&1" 2>&1
& $Kube exec $Pod -n loco -- sh -c "busybox ping -c 3 192.168.10.10 2>&1" 2>&1

Write-Host "=== DONE ==="
