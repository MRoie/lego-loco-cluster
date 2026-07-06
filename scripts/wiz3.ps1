$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
$BinDir = Join-Path $RepoRoot ".bin"
Remove-Item Env:\KUBECONFIG -ErrorAction SilentlyContinue
Set-Location $RepoRoot
$Kube = "$BinDir\kubectl.exe"
$Pod = "loco-loco-emulator-0"
New-Item -ItemType Directory -Force -Path "scripts\out" | Out-Null

function SendKey($k) {
  Write-Host "sendkey $k"
  & $Kube exec $Pod -n loco -- python3 /usr/local/bin/qmp-control.py sendkey $k 2>&1
  Start-Sleep -Milliseconds 600
}

SendKey "spc"   # untick Floppy disk drives (currently focused/checked)
SendKey "tab"   # move focus to CD-ROM drive checkbox
SendKey "spc"   # tick CD-ROM drive

Start-Sleep -Seconds 1
& $Kube exec $Pod -n loco -- python3 /usr/local/bin/qmp-control.py screendump /tmp/wiz3a.ppm 2>&1
& $Kube cp -n loco "${Pod}:tmp/wiz3a.ppm" "scripts/out/wiz3a.ppm" 2>&1
Write-Host "=== DONE ==="
