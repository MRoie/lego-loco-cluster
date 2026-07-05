$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
$BinDir = Join-Path $RepoRoot ".bin"
Remove-Item Env:\KUBECONFIG -ErrorAction SilentlyContinue
Set-Location $RepoRoot
$Kube = "$BinDir\kubectl.exe"
$Pod = "loco-loco-emulator-0"
New-Item -ItemType Directory -Force -Path "scripts\out" | Out-Null

Write-Host "=== insert CD ==="
& $Kube exec $Pod -n loco -- python3 /usr/local/bin/qmp-control.py hmp "change ide1-cd0 /images/win98se.iso" 2>&1

Write-Host "=== info block after insert ==="
& $Kube exec $Pod -n loco -- python3 /usr/local/bin/qmp-control.py hmp "info block" 2>&1

Write-Host "=== screendump current guest state ==="
& $Kube exec $Pod -n loco -- python3 /usr/local/bin/qmp-control.py screendump /tmp/state0.ppm 2>&1
& $Kube cp -n loco "${Pod}:tmp/state0.ppm" "scripts/out/state0.ppm" 2>&1

Write-Host "=== DONE ==="
