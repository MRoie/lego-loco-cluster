$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
$BinDir = Join-Path $RepoRoot ".bin"
Remove-Item Env:\KUBECONFIG -ErrorAction SilentlyContinue
Set-Location $RepoRoot
$Kube = "$BinDir\kubectl.exe"
$Pod = "loco-loco-emulator-0"

Write-Host "=== wait a bit more for savevm to flush ==="
Start-Sleep -Seconds 15

Write-Host "=== info-snapshots ==="
& $Kube exec $Pod -n loco -- python3 /usr/local/bin/qmp-control.py info-snapshots 2>&1

Write-Host "=== cont (resume VM in case still paused) ==="
& $Kube exec $Pod -n loco -- python3 /usr/local/bin/qmp-control.py cont 2>&1

Write-Host "=== DONE ==="
