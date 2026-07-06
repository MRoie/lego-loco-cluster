$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
$BinDir = Join-Path $RepoRoot ".bin"
$env:PATH = "$BinDir;$env:PATH"
$env:KUBECONFIG = Join-Path $RepoRoot ".kube-config"
Set-Location $RepoRoot

Write-Host "=== helm upgrade (CPU limit bump 2->3) ===" -ForegroundColor Cyan
for ($i = 1; $i -le 3; $i++) {
  & "$BinDir\helm.exe" upgrade --install loco helm/loco-chart -n loco -f helm/loco-chart/values-lan-test.yaml --timeout 5m
  if ($LASTEXITCODE -eq 0) { Write-Host "helm upgrade succeeded on attempt $i"; break }
  Write-Host "helm upgrade failed on attempt $i (exit $LASTEXITCODE), retrying in 15s..."
  Start-Sleep -Seconds 15
}

& "$BinDir\kubectl.exe" scale deployment/loco-loco-vr -n loco --replicas=0 2>&1 | Out-Null

Write-Host "=== Waiting for rollout ===" -ForegroundColor Cyan
& "$BinDir\kubectl.exe" rollout status statefulset/loco-loco-emulator -n loco --timeout=240s

Write-Host "=== Final pod status + resource check ===" -ForegroundColor Cyan
& "$BinDir\kubectl.exe" get pods -n loco -o wide
& "$BinDir\kubectl.exe" get pod loco-loco-emulator-0 -n loco -o jsonpath="{.spec.containers[0].resources}"
Write-Host ""

Write-Host "=== DONE ===" -ForegroundColor Green
