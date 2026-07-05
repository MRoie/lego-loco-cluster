$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
$BinDir = Join-Path $RepoRoot ".bin"
Remove-Item Env:\KUBECONFIG -ErrorAction SilentlyContinue
Set-Location $RepoRoot
$Kube = "$BinDir\kubectl.exe"
$Pod = "loco-loco-emulator-0"
New-Item -ItemType Directory -Force -Path "scripts\out" | Out-Null

Write-Host "sendkey ret (click Next on 'search for best driver' screen)"
& $Kube exec $Pod -n loco -- python3 /usr/local/bin/qmp-control.py sendkey ret 2>&1
Start-Sleep -Seconds 2
& $Kube exec $Pod -n loco -- python3 /usr/local/bin/qmp-control.py screendump /tmp/wiz2.ppm 2>&1
& $Kube cp -n loco "${Pod}:tmp/wiz2.ppm" "scripts/out/wiz2.ppm" 2>&1
Write-Host "=== DONE ==="
