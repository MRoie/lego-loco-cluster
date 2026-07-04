$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
$BinDir = Join-Path $RepoRoot ".bin"
$env:PATH = "$BinDir;$env:PATH"
$env:KUBECONFIG = Join-Path $RepoRoot ".kube-config"
Set-Location $RepoRoot

# Kill any stale kubectl port-forward processes first
Get-Process kubectl -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

# Resilient loop: restart port-forward if it drops
while ($true) {
  Write-Host "[$(Get-Date -Format 'HH:mm:ss')] starting port-forward frontend 3000"
  & "$BinDir\kubectl.exe" port-forward svc/loco-loco-frontend -n loco 3000:3000
  Write-Host "[$(Get-Date -Format 'HH:mm:ss')] port-forward exited, retrying in 3s"
  Start-Sleep -Seconds 3
}
