$ErrorActionPreference = 'Continue'
Write-Host "=== docker daemon ==="
docker version --format "server: {{.Server.Version}}" 2>&1 | Select-Object -First 3
Write-Host "=== docker ps (loco) ==="
docker ps --format "{{.Names}}  {{.Image}}  {{.Status}}" 2>&1 | Select-String -Pattern "loco|control-plane" | Select-Object -First 10
Write-Host "=== DONE ==="
