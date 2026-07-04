$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
$BinDir = Join-Path $RepoRoot ".bin"
$env:PATH = "$BinDir;$env:PATH"
$env:KUBECONFIG = Join-Path $RepoRoot ".kube-config"
Set-Location $RepoRoot

Write-Host "=== pods ===" -ForegroundColor Cyan
& "$BinDir\kubectl.exe" get pods -n loco -o wide

Write-Host "=== backend logs (tail 100) ===" -ForegroundColor Cyan
& "$BinDir\kubectl.exe" logs loco-loco-backend-6d5c978668-s7nh4 -n loco --tail=100

Write-Host "=== DONE ===" -ForegroundColor Green
