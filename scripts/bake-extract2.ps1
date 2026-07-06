$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
$BinDir = Join-Path $RepoRoot ".bin"
$env:PATH = "$BinDir;$env:PATH"
$env:KUBECONFIG = Join-Path $RepoRoot ".kube-config"
Set-Location $RepoRoot
$Kube = "$BinDir\kubectl.exe"
$pod = "loco-loco-emulator-0"

Write-Host "=== ensure QEMU running (resume if paused) ==="
& $Kube exec $pod -n loco -- python3 /usr/local/bin/qmp-control.py cont 2>&1
& $Kube exec $pod -n loco -- sh -c "rm -f /images/bake.qcow2 /images/bake2.qcow2; echo cleaned partials" 2>&1

Write-Host "=== pause, copy clean overlay, resume ==="
& $Kube exec $pod -n loco -- python3 /usr/local/bin/qmp-control.py stop 2>&1
& $Kube exec $pod -n loco -- sh -c "cp /images/win98_instance_0.qcow2 /images/bake2.qcow2 && echo copied && qemu-img info /images/bake2.qcow2 | head -20" 2>&1
& $Kube exec $pod -n loco -- python3 /usr/local/bin/qmp-control.py cont 2>&1

Write-Host "=== copy overlay to host build context ==="
$dst = "containers\qemu-softgpu\tmp-bake"
if (Test-Path $dst) { Remove-Item -Recurse -Force $dst }
New-Item -ItemType Directory -Path $dst | Out-Null
& $Kube cp -n loco "${pod}:images/bake2.qcow2" "$dst\overlay.qcow2" 2>&1
Write-Host "cp exit: $LASTEXITCODE"
if (Test-Path "$dst\overlay.qcow2") {
  $sz = [math]::Round((Get-Item "$dst\overlay.qcow2").Length/1MB,1)
  Write-Host "host overlay: $dst\overlay.qcow2  ${sz} MB"
}
& $Kube exec $pod -n loco -- sh -c "rm -f /images/bake2.qcow2; echo cleaned" 2>&1
Write-Host "=== DONE ==="
