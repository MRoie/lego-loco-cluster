$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
$BinDir = Join-Path $RepoRoot ".bin"
Remove-Item Env:\KUBECONFIG -ErrorAction SilentlyContinue
$Kube = "$BinDir\kubectl.exe"
Write-Host "=== pods ==="
& $Kube get pods -n loco -o wide --request-timeout=15s 2>&1
Write-Host "=== docker ps loco containers ==="
docker ps -a --filter "name=loco-loco" --format "table {{.Names}}\t{{.Status}}\t{{.Image}}" 2>&1
Write-Host "=== DONE ==="
