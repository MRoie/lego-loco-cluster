$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
$BinDir = Join-Path $RepoRoot ".bin"
Remove-Item Env:\KUBECONFIG -ErrorAction SilentlyContinue
Set-Location $RepoRoot
$Kube = "$BinDir\kubectl.exe"
$Pod = "loco-loco-emulator-0"

Write-Host "=== qmp-control.py help ==="
& $Kube exec $Pod -n loco -- python3 /usr/local/bin/qmp-control.py --help 2>&1

Write-Host "=== current block devices (hmp info block) ==="
& $Kube exec $Pod -n loco -- python3 /usr/local/bin/qmp-control.py hmp "info block" 2>&1

Write-Host "=== copying Win98 ISO into pod (this is ~600MB-700MB typically, may take a bit) ==="
$sw = [System.Diagnostics.Stopwatch]::StartNew()
& $Kube cp -n loco "containers\Windows 98 Second Edition.iso" "${Pod}:images/win98se.iso" 2>&1
Write-Host "cp took $($sw.Elapsed.TotalSeconds)s"

Write-Host "=== verify file landed ==="
& $Kube exec $Pod -n loco -- ls -lh /images/win98se.iso 2>&1

Write-Host "=== DONE ==="
