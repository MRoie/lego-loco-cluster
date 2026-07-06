$ErrorActionPreference = 'Continue'
Write-Host "=== start Docker Desktop ==="
Start-Process "C:\Program Files\Docker\Docker\Docker Desktop.exe"
Write-Host "started; waiting for daemon..."

$ok = $false
for ($i=0; $i -lt 40; $i++) {
  Start-Sleep -Seconds 10
  $v = docker version --format "{{.Server.Version}}" 2>$null
  if ($LASTEXITCODE -eq 0 -and $v) {
    Write-Host "[$($i*10)s] daemon up: server $v"
    # writability test
    docker pull hello-world:latest 2>&1 | Out-Null
    docker tag hello-world:latest loco-rwtest:probe 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) { Write-Host "WRITABLE"; docker rmi loco-rwtest:probe 2>&1 | Out-Null; $ok=$true; break }
    else { Write-Host "[$($i*10)s] daemon up but not writable yet" }
  } else {
    Write-Host "[$($i*10)s] daemon not ready yet"
  }
}
if ($ok) {
  Write-Host "=== fresh docker images (should be minimal) ==="
  docker images 2>&1
} else {
  Write-Host "=== TIMED OUT waiting for writable docker ==="
}
Write-Host "=== DONE ==="
