$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
$BinDir = Join-Path $RepoRoot ".bin"
Remove-Item Env:\KUBECONFIG -ErrorAction SilentlyContinue
$Kube = "$BinDir\kubectl.exe"

Write-Host "=== retagging backend/frontend to expected local tags ==="
docker tag ghcr.io/mroie/lego-loco-cluster/backend:latest lego-loco-backend:local 2>&1
docker tag ghcr.io/mroie/lego-loco-cluster/frontend:latest lego-loco-frontend:local 2>&1

Write-Host "=== scaling vr deployment to 0 (not needed for single-emulator validation) ==="
& $Kube scale deployment loco-loco-vr -n loco --replicas=0 2>&1

Write-Host "=== restart backend/frontend pods to pick up local tag ==="
& $Kube rollout restart deployment/loco-loco-backend -n loco 2>&1
& $Kube rollout restart deployment/loco-loco-frontend -n loco 2>&1

Start-Sleep -Seconds 8
Write-Host "=== pods now ==="
& $Kube get pods -n loco -o wide --request-timeout=15s 2>&1

Write-Host "=== DONE ==="
