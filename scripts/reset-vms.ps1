$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
$BinDir = Join-Path $RepoRoot ".bin"
$env:PATH = "$BinDir;$env:PATH"
$env:KUBECONFIG = Join-Path $RepoRoot ".kube-config"
Set-Location $RepoRoot
$Kube = "$BinDir\kubectl.exe"
foreach ($i in 0,1) {
  Write-Host "### reset loco-loco-emulator-$i"
  & $Kube exec "loco-loco-emulator-$i" -n loco -- python3 /usr/local/bin/qmp-control.py system-reset 2>&1
}
Write-Host "=== waiting for pods ready ==="
Start-Sleep -Seconds 20
& $Kube wait --for=condition=ready pod/loco-loco-emulator-0 pod/loco-loco-emulator-1 -n loco --timeout=300s 2>&1
Write-Host "=== DONE ==="
