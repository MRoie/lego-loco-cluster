$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
$BinDir = Join-Path $RepoRoot ".bin"
$env:PATH = "$BinDir;$env:PATH"
$env:KUBECONFIG = Join-Path $RepoRoot ".kube-config"
Set-Location $RepoRoot

Write-Host "=== Starting port-forward: localhost:3000 -> loco-loco-frontend:3000 ===" -ForegroundColor Cyan
& "$BinDir\kubectl.exe" port-forward svc/loco-loco-frontend -n loco 3000:3000
