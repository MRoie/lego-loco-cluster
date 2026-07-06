$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
$BinDir = Join-Path $RepoRoot ".bin"
$env:PATH = "$BinDir;$env:PATH"
$env:KUBECONFIG = Join-Path $RepoRoot ".kube-config"
Set-Location $RepoRoot

Write-Host "=== All processes in emulator-0 pod (with CPU%%) ===" -ForegroundColor Cyan
& "$BinDir\kubectl.exe" exec -n loco loco-loco-emulator-0 -- ps aux --sort=-%cpu 2>&1

Write-Host "=== VR deployment replica count (should be 0) ===" -ForegroundColor Cyan
& "$BinDir\kubectl.exe" get deployment -n loco loco-loco-vr -o jsonpath="{.spec.replicas} replicas, {.status.readyReplicas} ready`n" 2>&1

Write-Host "=== All pods across all namespaces (look for stragglers) ===" -ForegroundColor Cyan
& "$BinDir\kubectl.exe" get pods -A 2>&1

Write-Host "=== Docker Desktop VM overall load (top -bn1 first 20 lines) ===" -ForegroundColor Cyan
docker exec loco-control-plane sh -c "top -bn1 2>/dev/null | head -25" 2>&1

Write-Host "=== Windows host: top CPU processes ===" -ForegroundColor Cyan
Get-Process | Sort-Object CPU -Descending | Select-Object -First 15 Name, CPU, Id

Write-Host "=== DONE ===" -ForegroundColor Green
