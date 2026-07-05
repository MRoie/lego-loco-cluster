$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
$BinDir = Join-Path $RepoRoot ".bin"
Remove-Item Env:\KUBECONFIG -ErrorAction SilentlyContinue
Set-Location $RepoRoot
$Kube = "$BinDir\kubectl.exe"
$Pod = "loco-loco-emulator-0"
New-Item -ItemType Directory -Force -Path "containers\qemu-softgpu\tmp-bake" | Out-Null

Write-Host "=== QMP stop (pause VM for a consistent copy) ==="
& $Kube exec $Pod -n loco -- python3 /usr/local/bin/qmp-control.py stop 2>&1

Write-Host "=== make a copy of the instance qcow2 to flatten (leave the live one untouched) ==="
& $Kube exec $Pod -n loco -- sh -c "cp /images/win98_instance_0.qcow2 /images/win98_instance_0_flat.qcow2" 2>&1

Write-Host "=== QMP cont (resume VM immediately - don't leave it paused) ==="
& $Kube exec $Pod -n loco -- python3 /usr/local/bin/qmp-control.py cont 2>&1

Write-Host "=== rebase the copy to drop the backing file (merge backing chain in place) ==="
$sw = [System.Diagnostics.Stopwatch]::StartNew()
& $Kube exec $Pod -n loco -- sh -c "qemu-img rebase -f qcow2 -b '' /images/win98_instance_0_flat.qcow2 2>&1" 2>&1
Write-Host "rebase took $($sw.Elapsed.TotalSeconds)s"

Write-Host "=== verify no backing file remains, and snapshot list preserved ==="
& $Kube exec $Pod -n loco -- sh -c "qemu-img info /images/win98_instance_0_flat.qcow2 2>&1" 2>&1

Write-Host "=== copy flattened qcow2 out to host ==="
$sw2 = [System.Diagnostics.Stopwatch]::StartNew()
& $Kube cp -n loco "${Pod}:images/win98_instance_0_flat.qcow2" "containers\qemu-softgpu\tmp-bake\netready.qcow2" 2>&1
Write-Host "kubectl cp took $($sw2.Elapsed.TotalSeconds)s"

Write-Host "=== local file check ==="
Get-Item "containers\qemu-softgpu\tmp-bake\netready.qcow2" -ErrorAction SilentlyContinue | Select-Object Name,Length

Write-Host "=== DONE ==="
