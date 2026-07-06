$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
$BinDir = Join-Path $RepoRoot ".bin"
$env:PATH = "$BinDir;$env:PATH"
$env:KUBECONFIG = Join-Path $RepoRoot ".kube-config"
Set-Location $RepoRoot
$Kube = "$BinDir\kubectl.exe"

Write-Host "=== docker daemon ==="
docker version --format "server {{.Server.Version}}" 2>&1 | Select-Object -First 1
Write-Host "=== kind node container ==="
docker ps -a --format "{{.Names}}  {{.Status}}" 2>&1 | Select-String "control-plane"
Write-Host "=== pods ==="
& $Kube get pods -n loco -o wide 2>&1
Write-Host "=== emulator /images contents + qcow2 age ==="
foreach ($i in 0,1) {
  Write-Host "--- loco-loco-emulator-$i ---"
  & $Kube exec "loco-loco-emulator-$i" -n loco -- sh -c "ls -lh /images/ 2>&1; echo '--- qcow2 snapshots inside ---'; for f in /images/win98_instance_$i.qcow2; do qemu-img snapshot -l `$f 2>&1 || echo 'no snapshots'; done" 2>&1
}
Write-Host "=== win98 CD present on node? ==="
docker exec loco-control-plane ls -lh /opt/win98se.iso 2>&1
Write-Host "=== QEMU cmdline (cdrom attached?) ==="
foreach ($i in 0,1) {
  & $Kube exec "loco-loco-emulator-$i" -n loco -- sh -c "tr '\0' ' ' < /proc/`$(pgrep -f qemu-system | head -1)/cmdline; echo" 2>&1
}
Write-Host "=== images available (host + node) ==="
docker images --format "{{.Repository}}:{{.Tag}}  {{.Size}}" 2>&1 | Select-String "loco|win98|ghcr|backend|frontend" | Select-Object -First 20
Write-Host "--- node containerd images ---"
docker exec loco-control-plane crictl images 2>&1 | Select-String "loco|emulator|backend|frontend|win98" | Select-Object -First 20
Write-Host "=== DONE ==="
