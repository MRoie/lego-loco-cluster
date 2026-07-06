$ErrorActionPreference = 'Continue'
Set-Location "G:\dev\lego-loco-cluster"
$date = Get-Date -Format "yyyyMMdd"
$repo = "ghcr.io/mroie/lego-loco-cluster"

Write-Host "=== tag backend (from :test) ==="
docker tag "${repo}/backend:test" "${repo}/backend:$date" 2>&1
docker tag "${repo}/backend:test" "${repo}/backend:latest" 2>&1

Write-Host "=== PUSH backend:$date ==="
docker push "${repo}/backend:$date" 2>&1 | Select-Object -Last 2
Write-Host "=== PUSH backend:latest ==="
docker push "${repo}/backend:latest" 2>&1 | Select-Object -Last 2
Write-Host "=== PUSH frontend:$date ==="
docker push "${repo}/frontend:$date" 2>&1 | Select-Object -Last 2
Write-Host "=== PUSH frontend:latest ==="
docker push "${repo}/frontend:latest" 2>&1 | Select-Object -Last 2

Write-Host "=== remote digests (confirm on GHCR) ==="
foreach ($t in @("${repo}/backend:latest","${repo}/frontend:latest")) {
  Write-Host "--- $t ---"
  docker manifest inspect $t 2>&1 | Select-String "digest" | Select-Object -First 1
}
Write-Host "=== DONE ==="
