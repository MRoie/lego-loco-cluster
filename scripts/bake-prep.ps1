$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
$BinDir = Join-Path $RepoRoot ".bin"
$env:PATH = "$BinDir;$env:PATH"
$env:KUBECONFIG = Join-Path $RepoRoot ".kube-config"
Set-Location $RepoRoot
$Kube = "$BinDir\kubectl.exe"

Write-Host "=== instance-0 qcow2 backing chain ==="
& $Kube exec loco-loco-emulator-0 -n loco -- sh -c "qemu-img info -U /images/win98_instance_0.qcow2 2>&1; echo '--- backing base ---'; ls -lh /opt/builtin-images/ 2>&1" 2>&1
Write-Host "=== node disk free ==="
docker exec loco-control-plane sh -c "df -h /var 2>&1; echo '--- /images in pod is emptyDir on node ---'" 2>&1
& $Kube exec loco-loco-emulator-0 -n loco -- sh -c "df -h /images 2>&1" 2>&1
Write-Host "=== host free space on G: (for cp target) ==="
Get-PSDrive G | Select-Object Used,Free
Write-Host "=== existing softgpu image builtin size ==="
docker exec loco-control-plane crictl images 2>&1 | Select-String "win98-softgpu"
Write-Host "=== DONE ==="
