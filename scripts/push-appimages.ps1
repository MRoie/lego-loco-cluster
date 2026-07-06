$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
Set-Location $RepoRoot
$date = Get-Date -Format "yyyyMMdd"
$owner = "mroie"
$repo = "ghcr.io/$owner/lego-loco-cluster"

Write-Host "=== image store readable? ==="
docker images --format "{{.Repository}}:{{.Tag}}  {{.ID}}  {{.Size}}" 2>&1 | Select-String "lego-loco|win98-softgpu" | Select-Object -First 20

function TagPush($src, $target) {
  Write-Host "--- $src -> $target ---"
  docker tag $src $target 2>&1
  if ($LASTEXITCODE -ne 0) { Write-Host "TAG FAILED for $src"; return }
  docker push $target 2>&1 | Select-Object -Last 4
  Write-Host "push exit: $LASTEXITCODE"
}

Write-Host "=== BACKEND ==="
TagPush "lego-loco-backend:v15-agents" "${repo}/backend:v15-agents"
TagPush "lego-loco-backend:v15-agents" "${repo}/backend:latest"

Write-Host "=== FRONTEND ==="
TagPush "lego-loco-frontend:local" "${repo}/frontend:$date"
TagPush "lego-loco-frontend:local" "${repo}/frontend:latest"

Write-Host "=== resulting digests ==="
foreach ($t in @("${repo}/backend:latest","${repo}/frontend:latest")) {
  Write-Host "--- $t ---"
  docker manifest inspect $t 2>&1 | Select-String "digest" | Select-Object -First 2
}
Write-Host "=== DONE ==="
