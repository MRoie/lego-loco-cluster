$ErrorActionPreference = 'Continue'
Write-Host "=== active containers (build steps run as temp containers) ==="
docker ps -a --format "{{.Image}}  {{.Command}}  {{.Status}}" 2>&1 | Select-Object -First 15
Write-Host "=== images so far ==="
docker images 2>&1 | Select-Object -First 15
Write-Host "=== disk usage ==="
docker system df 2>&1
Write-Host "=== DONE ==="
