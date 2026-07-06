$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
$BinDir = Join-Path $RepoRoot ".bin"
$env:PATH = "$BinDir;$env:PATH"
$env:KUBECONFIG = Join-Path $RepoRoot ".kube-config"

Write-Host "=== Deleting any existing 'loco' kind cluster ===" -ForegroundColor Cyan
& "$BinDir\kind.exe" delete cluster --name loco

Write-Host "=== Creating kind cluster 'loco' ===" -ForegroundColor Cyan
& "$BinDir\kind.exe" create cluster --name loco --wait 180s

Write-Host "=== Cluster info ===" -ForegroundColor Cyan
& "$BinDir\kubectl.exe" cluster-info --context kind-loco
& "$BinDir\kubectl.exe" get nodes -o wide

Write-Host "=== DONE ===" -ForegroundColor Green
