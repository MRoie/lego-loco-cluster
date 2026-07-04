$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
$BinDir = Join-Path $RepoRoot ".bin"
$env:PATH = "$BinDir;$env:PATH"
$env:KUBECONFIG = Join-Path $RepoRoot ".kube-config"
Set-Location $RepoRoot

Write-Host "=== Backend logs (last 80 lines) ===" -ForegroundColor Cyan
& "$BinDir\kubectl.exe" logs deployment/loco-loco-backend -n loco --tail=80

Write-Host "=== Frontend logs (last 40 lines) ===" -ForegroundColor Cyan
& "$BinDir\kubectl.exe" logs deployment/loco-loco-frontend -n loco --tail=40

Write-Host "=== DONE ===" -ForegroundColor Green
