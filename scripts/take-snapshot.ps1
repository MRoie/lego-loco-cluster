$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
$BinDir = Join-Path $RepoRoot ".bin"
Remove-Item Env:\KUBECONFIG -ErrorAction SilentlyContinue
Set-Location $RepoRoot
$Kube = "$BinDir\kubectl.exe"
$Pod = "loco-loco-emulator-0"

Write-Host "=== existing snapshots before ==="
& $Kube exec $Pod -n loco -- python3 /usr/local/bin/qmp-control.py info-snapshots 2>&1

Write-Host "=== savevm netready (clean desktop, NIC driver installed, network verified) ==="
& $Kube exec $Pod -n loco -- python3 /usr/local/bin/qmp-control.py savevm netready 2>&1

Write-Host "=== snapshots after ==="
& $Kube exec $Pod -n loco -- python3 /usr/local/bin/qmp-control.py info-snapshots 2>&1

Write-Host "=== DONE ==="
