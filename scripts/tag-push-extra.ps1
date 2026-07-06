$ErrorActionPreference = 'Continue'
Set-Location "G:\dev\lego-loco-cluster"
$Repo = "ghcr.io/mroie/lego-loco-cluster/emulator-snapshot"

Write-Host "=== current local tags for this image ==="
docker images $Repo 2>&1

Write-Host "=== tag :win98-softgpu (same digest) ==="
docker tag "${Repo}:netready" "${Repo}:win98-softgpu" 2>&1

Write-Host "=== push :win98-softgpu ==="
docker push "${Repo}:win98-softgpu" 2>&1

Write-Host "=== confirm digest matches ==="
docker manifest inspect "${Repo}:win98-softgpu" 2>&1 | Select-String "digest"
docker manifest inspect "${Repo}:netready" 2>&1 | Select-String "digest"

Write-Host "=== DONE ==="
