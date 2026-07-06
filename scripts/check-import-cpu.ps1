$ErrorActionPreference = 'Continue'
$proc = Get-Process -Id 10592 -ErrorAction SilentlyContinue
if ($proc) {
  $cpu1 = $proc.CPU
  Write-Host "docker exec (ctr import) CPU time (sample 1): $cpu1"
  Start-Sleep -Seconds 8
  $proc.Refresh()
  $cpu2 = $proc.CPU
  Write-Host "docker exec (ctr import) CPU time (sample 2, +8s): $cpu2"
  Write-Host "Delta: $($cpu2 - $cpu1) seconds of CPU used in 8 wall-clock seconds"
} else {
  Write-Host "PID 10592 no longer exists (likely finished!)"
}

Write-Host "=== docker exec loco-control-plane ctr -n k8s.io images list ===" -ForegroundColor Cyan
docker exec loco-control-plane ctr -n k8s.io images list 2>&1 | Select-String "lego-loco-emulator"

Write-Host "=== pod status ===" -ForegroundColor Cyan
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
$BinDir = Join-Path $RepoRoot ".bin"
$env:PATH = "$BinDir;$env:PATH"
$env:KUBECONFIG = Join-Path $RepoRoot ".kube-config"
& "$BinDir\kubectl.exe" get pods -n loco -o wide

Write-Host "=== DONE ===" -ForegroundColor Green
