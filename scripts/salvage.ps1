$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
Set-Location $RepoRoot
$node = "loco-control-plane"

Write-Host "=== locate NIC qcow2 + base on node (read-only OK for find) ==="
docker exec $node sh -c "find /var/lib/kubelet -name 'win98_instance_0.qcow2' 2>/dev/null; find /var/lib/kubelet -name 'bake*.qcow2' 2>/dev/null" 2>&1
Write-Host "--- base builtin location ---"
docker exec $node sh -c "find / -name 'win98.qcow2.builtin' 2>/dev/null | head -3" 2>&1

Write-Host "=== can we READ the overlay? (dd first 1MB) ==="
docker exec $node sh -c "O=`$(find /var/lib/kubelet -name 'win98_instance_0.qcow2' 2>/dev/null | head -1); echo overlay=`$O; dd if=`$O of=/dev/null bs=1M count=1 2>&1 && echo READ-OK || echo READ-FAIL" 2>&1

Write-Host "=== DONE locate ==="
