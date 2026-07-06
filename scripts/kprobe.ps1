$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
$BinDir = Join-Path $RepoRoot ".bin"
Write-Host "=== kindest/node image present? ==="
docker images 2>&1 | Select-String "kindest"
Write-Host "=== containers (kind node?) ==="
docker ps -a --format "{{.Names}} {{.Image}} {{.Status}}" 2>&1 | Select-String "loco|kindest"
Write-Host "=== kind clusters ==="
& "$BinDir\kind.exe" get clusters 2>&1
Write-Host "=== docker pull activity (recent images) ==="
docker images --format "{{.Repository}}:{{.Tag}} {{.CreatedSince}}" 2>&1 | Select-Object -First 6
Write-Host "=== DONE ==="
