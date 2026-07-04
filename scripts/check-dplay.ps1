$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
$BinDir = Join-Path $RepoRoot ".bin"
$env:PATH = "$BinDir;$env:PATH"
$env:KUBECONFIG = Join-Path $RepoRoot ".kube-config"
Set-Location $RepoRoot
$Kube = "$BinDir\kubectl.exe"

Write-Host "=== DirectPlay ports on guests (from opposite pods) ==="
& $Kube exec loco-loco-emulator-1 -n loco -- sh -c "for p in 47624 2300 2350; do nc -z -v -w2 192.168.10.10 `$p 2>&1; done" 2>&1
& $Kube exec loco-loco-emulator-0 -n loco -- sh -c "for p in 47624 2300 2350; do nc -z -v -w2 192.168.10.11 `$p 2>&1; done" 2>&1
Write-Host "=== DONE ==="
