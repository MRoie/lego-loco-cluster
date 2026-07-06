$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
$BinDir = Join-Path $RepoRoot ".bin"
$env:PATH = "$BinDir;$env:PATH"
$env:KUBECONFIG = Join-Path $RepoRoot ".kube-config"
Set-Location $RepoRoot
$Kube = "$BinDir\kubectl.exe"
New-Item -ItemType Directory -Force -Path "scripts\out" | Out-Null

function SendKey($podName, $keyName) {
  & $Kube exec $podName -n loco -- python3 /usr/local/bin/qmp-control.py sendkey $keyName 2>&1 | Out-Null
  Start-Sleep -Milliseconds 300
}

foreach ($i in 0,1) {
  $pod = "loco-loco-emulator-$i"
  Write-Host "### $pod : dismiss network logon with OK (Enter), then Run -> winipcfg ###"
  SendKey $pod "ret"
  Start-Sleep -Seconds 12
  SendKey $pod "ctrl-esc"
  Start-Sleep -Seconds 2
  SendKey $pod "r"
  Start-Sleep -Seconds 2
  foreach ($kk in "w","i","n","i","p","c","f","g") { SendKey $pod $kk }
  SendKey $pod "ret"
  Start-Sleep -Seconds 8

  Write-Host "### $pod : after screendump ###"
  & $Kube exec $pod -n loco -- python3 /usr/local/bin/qmp-control.py screendump /tmp/scr-after.ppm 2>&1
  & $Kube cp -n loco "${pod}:tmp/scr-after.ppm" "scripts/out/scr$i-after.ppm" 2>&1
}
Write-Host "=== DONE ==="
