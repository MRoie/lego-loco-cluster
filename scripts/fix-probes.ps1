$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
$BinDir = Join-Path $RepoRoot ".bin"
$env:PATH = "$BinDir;$env:PATH"
$env:KUBECONFIG = Join-Path $RepoRoot ".kube-config"
Set-Location $RepoRoot

Write-Host "=== helm upgrade with loosened probes ===" -ForegroundColor Cyan
& "$BinDir\helm.exe" upgrade --install loco helm/loco-chart -n loco -f helm/loco-chart/values-lan-test.yaml --timeout 5m
Write-Host "helm exit: $LASTEXITCODE"

Write-Host "=== scale down VR (chart gap workaround) ===" -ForegroundColor Cyan
& "$BinDir\kubectl.exe" scale deployment/loco-loco-vr -n loco --replicas=0

Write-Host "=== waiting 20s ===" -ForegroundColor Cyan
Start-Sleep -Seconds 20
& "$BinDir\kubectl.exe" get pods -n loco -o wide

Write-Host "=== DONE ===" -ForegroundColor Green
