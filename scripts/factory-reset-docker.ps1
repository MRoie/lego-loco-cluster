$ErrorActionPreference = 'Continue'
Write-Host "=== 1. quit Docker Desktop + backend processes ==="
taskkill /F /IM "Docker Desktop.exe" 2>&1
taskkill /F /IM "com.docker.backend.exe" 2>&1
taskkill /F /IM "com.docker.build.exe" 2>&1
taskkill /F /IM "com.docker.dev-envs.exe" 2>&1
taskkill /F /IM "dockerd.exe" 2>&1
Start-Sleep -Seconds 4

Write-Host "=== 2. wsl --shutdown (stop distros so they can be unregistered) ==="
wsl --shutdown 2>&1
Start-Sleep -Seconds 6
Write-Host "--- distro states after shutdown ---"
wsl -l -v 2>&1

Write-Host "=== 3. unregister corrupted data distro (factory reset of images/containers) ==="
wsl --unregister docker-desktop-data 2>&1
Write-Host "unregister exit: $LASTEXITCODE"
Start-Sleep -Seconds 3

Write-Host "=== 4. verify data distro is gone ==="
wsl -l -v 2>&1
Write-Host "=== DONE ==="
