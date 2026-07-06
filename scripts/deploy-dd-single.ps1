$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
$BinDir = Join-Path $RepoRoot ".bin"
Set-Location $RepoRoot
$Kube = "$BinDir\kubectl.exe"
$Helm = "$BinDir\helm.exe"

Write-Host "=== use docker-desktop context (default kubeconfig, NOT .kube-config) ==="
Remove-Item Env:\KUBECONFIG -ErrorAction SilentlyContinue
& $Kube config use-context docker-desktop 2>&1
& $Kube config current-context 2>&1

Write-Host "=== ensure namespace loco exists ==="
& $Kube create namespace loco 2>&1

Write-Host "=== helm upgrade --install (single replica, images already local) ==="
& $Helm upgrade --install loco "helm\loco-chart" -n loco -f "helm\loco-chart\values-dd-single.yaml" 2>&1

Write-Host "=== wait a bit, then pod status ==="
Start-Sleep -Seconds 5
& $Kube get pods -n loco -o wide 2>&1

Write-Host "=== DONE ==="
