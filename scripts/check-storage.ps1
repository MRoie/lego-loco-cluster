$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
$BinDir = Join-Path $RepoRoot ".bin"
$env:PATH = "$BinDir;$env:PATH"
$env:KUBECONFIG = Join-Path $RepoRoot ".kube-config"
Set-Location $RepoRoot
$Kube = "$BinDir\kubectl.exe"

Write-Host "=== PVCs ==="
& $Kube get pvc -n loco 2>&1
Write-Host "=== PVs ==="
& $Kube get pv 2>&1
Write-Host "=== StatefulSet volumes ==="
& $Kube get statefulset loco-loco-emulator -n loco -o jsonpath="{.spec.template.spec.volumes}" 2>&1
Write-Host ""
Write-Host "=== StatefulSet env ==="
& $Kube get statefulset loco-loco-emulator -n loco -o jsonpath="{.spec.template.spec.containers[0].env}" 2>&1
Write-Host ""
Write-Host "=== /images in pod 0 ==="
& $Kube exec loco-loco-emulator-0 -n loco -- ls -lh /images /images/snapshots 2>&1
Write-Host "=== /images in pod 1 ==="
& $Kube exec loco-loco-emulator-1 -n loco -- ls -lh /images 2>&1
Write-Host "=== host ISO file ==="
Get-Item "containers\Windows 98 Second Edition.iso" | Select-Object Name,Length
Write-Host "=== DONE ==="
