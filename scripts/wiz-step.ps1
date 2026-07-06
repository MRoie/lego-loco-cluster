$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
$BinDir = Join-Path $RepoRoot ".bin"
Remove-Item Env:\KUBECONFIG -ErrorAction SilentlyContinue
Set-Location $RepoRoot
$Kube = "$BinDir\kubectl.exe"
$Pod = "loco-loco-emulator-0"
New-Item -ItemType Directory -Force -Path "scripts\out" | Out-Null

# Usage: wiz-step.ps1 <dumpname> [keys...]
$DumpName = $args[0]
$Keys = $args[1..($args.Count-1)]

foreach ($k in $Keys) {
  Write-Host "sendkey $k"
  & $Kube exec $Pod -n loco -- python3 /usr/local/bin/qmp-control.py sendkey $k 2>&1
  Start-Sleep -Milliseconds 500
}
Start-Sleep -Seconds 1
& $Kube exec $Pod -n loco -- python3 /usr/local/bin/qmp-control.py screendump "/tmp/$DumpName.ppm" 2>&1
& $Kube cp -n loco "${Pod}:tmp/$DumpName.ppm" "scripts/out/$DumpName.ppm" 2>&1
Write-Host "=== DONE ==="
