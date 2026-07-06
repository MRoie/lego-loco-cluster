$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
$BinDir = Join-Path $RepoRoot ".bin"
Remove-Item Env:\KUBECONFIG -ErrorAction SilentlyContinue
$Kube = "$BinDir\kubectl.exe"

Write-Host "=== pods ==="
& $Kube get pods -n loco -o wide 2>&1

Write-Host "=== emulator-0 describe (why pending?) ==="
& $Kube describe pod loco-loco-emulator-0 -n loco 2>&1

Write-Host "=== events ==="
& $Kube get events -n loco --sort-by=.lastTimestamp 2>&1 | Select-Object -Last 30

Write-Host "=== DONE ==="
