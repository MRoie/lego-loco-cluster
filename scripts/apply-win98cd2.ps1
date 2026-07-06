$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
$BinDir = Join-Path $RepoRoot ".bin"
$env:PATH = "$BinDir;$env:PATH"
$env:KUBECONFIG = Join-Path $RepoRoot ".kube-config"
Set-Location $RepoRoot
$Kube = "$BinDir\kubectl.exe"

Write-Host "=== 0. Kill stuck apply-win98cd script/docker cp ==="
Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match 'apply-win98cd\.ps1' -or ($_.Name -eq 'docker.exe' -and $_.CommandLine -match 'docker\s+cp') } | ForEach-Object { Write-Host "killing $($_.ProcessId) $($_.Name)"; Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

Write-Host "=== 1. Verify ISO on node ==="
docker exec loco-control-plane ls -lh /opt/win98se.iso

Write-Host "=== 2. Patch statefulset ==="
& $Kube patch statefulset loco-loco-emulator -n loco --patch-file scripts\win98cd-patch.yaml 2>&1

Write-Host "=== 3. Delete pods ==="
& $Kube delete pod loco-loco-emulator-0 loco-loco-emulator-1 -n loco --wait=false 2>&1

Write-Host "=== 4. Wait ready ==="
& $Kube wait --for=condition=ready pod/loco-loco-emulator-0 pod/loco-loco-emulator-1 -n loco --timeout=300s 2>&1

Write-Host "=== 5. Verify QEMU cmdline ==="
Start-Sleep -Seconds 45
foreach ($i in 0,1) {
  & $Kube exec "loco-loco-emulator-$i" -n loco -- sh -c "tr '\0' ' ' < /proc/`$(pgrep -f qemu-system | head -1)/cmdline; echo" 2>&1
}
Write-Host "=== DONE ==="
