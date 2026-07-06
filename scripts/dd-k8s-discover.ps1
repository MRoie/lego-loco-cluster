$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
$BinDir = Join-Path $RepoRoot ".bin"

Write-Host "=== docker images (local cache - what's already available to Docker Desktop K8s) ==="
docker images 2>&1

Write-Host "=== kubectl contexts ==="
& "$BinDir\kubectl.exe" config get-contexts 2>&1

Write-Host "=== switch to docker-desktop context ==="
& "$BinDir\kubectl.exe" config use-context docker-desktop 2>&1

Write-Host "=== docker-desktop nodes ==="
& "$BinDir\kubectl.exe" get nodes -o wide 2>&1

Write-Host "=== namespaces ==="
& "$BinDir\kubectl.exe" get ns 2>&1

Write-Host "=== any existing loco releases/resources on docker-desktop ==="
& "$BinDir\helm.exe" list -A 2>&1
& "$BinDir\kubectl.exe" get all -n loco 2>&1

Write-Host "=== helm chart values files available ==="
Get-ChildItem "$RepoRoot\helm\loco-chart" -Recurse -Filter "values*.yaml" -ErrorAction SilentlyContinue | Select-Object FullName

Write-Host "=== GHCR remote tags check (win98-softgpu) - requires docker login already done ==="
docker manifest inspect ghcr.io/mroie/lego-loco-cluster/win98-softgpu:latest 2>&1 | Select-Object -First 5
Write-Host "--- trying to list via docker (best effort) ---"

Write-Host "=== .dockertemp flattened tar leftovers ==="
Get-ChildItem "G:\dev\.dockertemp" -ErrorAction SilentlyContinue | Select-Object Name,Length,LastWriteTime

Write-Host "=== DONE ==="
