$ErrorActionPreference = 'Continue'
Set-Location "G:\dev\lego-loco-cluster"
$targets = @(
  "ghcr.io/mroie/lego-loco-cluster/backend:v15-agents",
  "ghcr.io/mroie/lego-loco-cluster/backend:latest",
  "ghcr.io/mroie/lego-loco-cluster/frontend:20260705",
  "ghcr.io/mroie/lego-loco-cluster/frontend:latest"
)
foreach ($t in $targets) {
  Write-Host "=== PUSH $t ==="
  docker push $t 2>&1 | Select-Object -Last 6
  Write-Host "exit: $LASTEXITCODE"
}
Write-Host "=== DONE ==="
