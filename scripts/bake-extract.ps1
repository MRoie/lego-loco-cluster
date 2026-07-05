$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
$BinDir = Join-Path $RepoRoot ".bin"
$env:PATH = "$BinDir;$env:PATH"
$env:KUBECONFIG = Join-Path $RepoRoot ".kube-config"
Set-Location $RepoRoot
$Kube = "$BinDir\kubectl.exe"
$pod = "loco-loco-emulator-0"

Write-Host "=== 1. pause QEMU (quiesce disk) ==="
& $Kube exec $pod -n loco -- python3 /usr/local/bin/qmp-control.py stop 2>&1

Write-Host "=== 2. copy overlay (preserves internal snapshots) ==="
& $Kube exec $pod -n loco -- sh -c "rm -f /images/bake.qcow2; cp /images/win98_instance_0.qcow2 /images/bake.qcow2 && echo copied && ls -lh /images/bake.qcow2" 2>&1

Write-Host "=== 3. flatten: pull backing base into bake.qcow2 (standalone, snapshots kept) ==="
& $Kube exec $pod -n loco -- sh -c "qemu-img rebase -b '' /images/bake.qcow2 && echo rebased" 2>&1

Write-Host "=== 4. resume QEMU ==="
& $Kube exec $pod -n loco -- python3 /usr/local/bin/qmp-control.py cont 2>&1

Write-Host "=== 5. verify bake.qcow2 (no backing file, snapshots present) ==="
& $Kube exec $pod -n loco -- sh -c "qemu-img info /images/bake.qcow2 2>&1" 2>&1

Write-Host "=== 6. copy bake.qcow2 to host build context ==="
$dst = "containers\qemu-softgpu\tmp-bake"
if (Test-Path $dst) { Remove-Item -Recurse -Force $dst }
New-Item -ItemType Directory -Path $dst | Out-Null
& $Kube cp -n loco "${pod}:images/bake.qcow2" "$dst\win98.qcow2.builtin" 2>&1
Write-Host "cp exit: $LASTEXITCODE"
if (Test-Path "$dst\win98.qcow2.builtin") {
  $sz = [math]::Round((Get-Item "$dst\win98.qcow2.builtin").Length/1MB,1)
  Write-Host "host file: $dst\win98.qcow2.builtin  ${sz} MB"
}

Write-Host "=== 7. cleanup pod copy ==="
& $Kube exec $pod -n loco -- sh -c "rm -f /images/bake.qcow2; echo cleaned" 2>&1
Write-Host "=== DONE ==="
