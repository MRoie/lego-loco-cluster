$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
$BinDir = Join-Path $RepoRoot ".bin"
$env:PATH = "$BinDir;$env:PATH"
$env:KUBECONFIG = Join-Path $RepoRoot ".kube-config"
Set-Location $RepoRoot

Write-Host "=== current backend pod ===" -ForegroundColor Cyan
& "$BinDir\kubectl.exe" get pods -n loco -l app.kubernetes.io/component=backend -o wide

Write-Host "=== backend logs tail (current, live) ===" -ForegroundColor Cyan
& "$BinDir\kubectl.exe" logs -n loco -l app.kubernetes.io/component=backend --tail=150

Write-Host "=== DONE ===" -ForegroundColor Green
