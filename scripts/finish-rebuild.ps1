$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
$BinDir = Join-Path $RepoRoot ".bin"
$env:PATH = "$BinDir;$env:PATH"
$env:KUBECONFIG = Join-Path $RepoRoot ".kube-config"
Set-Location $RepoRoot

Write-Host "=== Checking cluster reachability ===" -ForegroundColor Cyan
& "$BinDir\kubectl.exe" get nodes
Write-Host "exit: $LASTEXITCODE"

Write-Host "=== Step 4: helm upgrade (applies bumped CPU limit + new image already loaded into kind) ===" -ForegroundColor Cyan
& "$BinDir\helm.exe" upgrade --install loco helm/loco-chart -n loco -f helm/loco-chart/values-lan-test.yaml --timeout 5m
Write-Host "helm exit: $LASTEXITCODE"

& "$BinDir\kubectl.exe" scale deployment/loco-loco-vr -n loco --replicas=0 2>&1 | Out-Null

Write-Host "=== Step 5: Restart emulator statefulset (both instances) ===" -ForegroundColor Cyan
& "$BinDir\kubectl.exe" rollout restart statefulset/loco-loco-emulator -n loco
Write-Host "rollout exit: $LASTEXITCODE"

Write-Host "=== Waiting for rollout ===" -ForegroundColor Cyan
& "$BinDir\kubectl.exe" rollout status statefulset/loco-loco-emulator -n loco --timeout=240s

Write-Host "=== Final pod status ===" -ForegroundColor Cyan
& "$BinDir\kubectl.exe" get pods -n loco -o wide

Write-Host "=== DONE ===" -ForegroundColor Green
