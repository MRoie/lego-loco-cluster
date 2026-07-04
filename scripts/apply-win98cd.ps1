$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
$BinDir = Join-Path $RepoRoot ".bin"
$env:PATH = "$BinDir;$env:PATH"
$env:KUBECONFIG = Join-Path $RepoRoot ".kube-config"
Set-Location $RepoRoot
$Kube = "$BinDir\kubectl.exe"

Write-Host "=== 1. Copy Win98 ISO to kind node ==="
docker cp "containers\Windows 98 Second Edition.iso" loco-control-plane:/opt/win98se.iso
Write-Host "docker cp exit: $LASTEXITCODE"
docker exec loco-control-plane ls -lh /opt/win98se.iso

Write-Host "=== 2. Patch statefulset (CD volume + QEMU_EXTRA_ARGS) ==="
& $Kube patch statefulset loco-loco-emulator -n loco --patch-file scripts\win98cd-patch.yaml 2>&1

Write-Host "=== 3. Delete pods to trigger restart with new spec ==="
& $Kube delete pod loco-loco-emulator-0 loco-loco-emulator-1 -n loco --wait=false 2>&1

Write-Host "=== 4. Wait for pods ready (up to 5 min) ==="
& $Kube wait --for=condition=ready pod/loco-loco-emulator-0 pod/loco-loco-emulator-1 -n loco --timeout=300s 2>&1

Write-Host "=== 5. Verify QEMU cmdline has cdrom ==="
Start-Sleep -Seconds 40
foreach ($i in 0,1) {
  & $Kube exec "loco-loco-emulator-$i" -n loco -- sh -c "tr '\0' ' ' < /proc/`$(pgrep -f qemu-system | head -1)/cmdline; echo" 2>&1
}
Write-Host "=== DONE ==="
