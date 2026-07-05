$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
Set-Location $RepoRoot
$Ctx = "containers\qemu-softgpu\tmp-bake"
$Repo = "ghcr.io/mroie/lego-loco-cluster/emulator-snapshot"

Write-Host "=== build context contents ==="
Get-ChildItem $Ctx | Select-Object Name,Length

Write-Host "=== docker build (FROM scratch + COPY qcow2) ==="
$sw = [System.Diagnostics.Stopwatch]::StartNew()
docker build -f "$Ctx\Dockerfile.snapshot" -t "${Repo}:netready" -t "${Repo}:20260705" -t "${Repo}:latest" "$Ctx" 2>&1
Write-Host "build took $($sw.Elapsed.TotalSeconds)s"

Write-Host "=== images ==="
docker images $Repo 2>&1

Write-Host "=== docker push :netready ==="
$sw2 = [System.Diagnostics.Stopwatch]::StartNew()
docker push "${Repo}:netready" 2>&1
Write-Host "push netready took $($sw2.Elapsed.TotalSeconds)s"

Write-Host "=== docker push :20260705 ==="
docker push "${Repo}:20260705" 2>&1

Write-Host "=== docker push :latest ==="
docker push "${Repo}:latest" 2>&1

Write-Host "=== DONE ==="
