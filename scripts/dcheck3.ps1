$ErrorActionPreference = 'Continue'
Write-Host "=== docker daemon ==="
docker version --format "server {{.Server.Version}}" 2>&1 | Select-Object -First 1
Write-Host "=== docker writable test (tag hello) ==="
docker images -q 2>&1 | Select-Object -First 1 | ForEach-Object {
  docker tag $_ loco-rwtest:probe 2>&1
  if ($LASTEXITCODE -eq 0) { Write-Host "WRITABLE"; docker rmi loco-rwtest:probe 2>&1 | Out-Null } else { Write-Host "STILL-READ-ONLY" }
}
Write-Host "=== loco images present ==="
docker images --format "{{.Repository}}:{{.Tag}}  {{.Size}}" 2>&1 | Select-String "lego-loco|win98-softgpu" | Select-Object -First 20
Write-Host "=== kind node ==="
docker ps -a --format "{{.Names}}  {{.Status}}" 2>&1 | Select-String "control-plane"
Write-Host "=== node fs writable? ==="
docker exec loco-control-plane sh -c "touch /var/lib/rwtest 2>&1 && echo NODE-WRITABLE && rm -f /var/lib/rwtest || echo NODE-READ-ONLY" 2>&1
Write-Host "=== DONE ==="
