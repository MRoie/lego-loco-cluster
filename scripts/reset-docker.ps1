# Reset Docker Desktop and wait for it to be ready
# Usage: powershell.exe -ExecutionPolicy Bypass -File reset-docker.ps1

Write-Host "Killing Docker processes..."
Get-Process '*docker*','*com.docker*','*vpnkit*' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3

Write-Host "Shutting down WSL..."
wsl --shutdown 2>&1 | Out-Null
Start-Sleep -Seconds 5

Write-Host "Starting Docker Desktop..."
Start-Process 'C:\Program Files\Docker\Docker\Docker Desktop.exe'
Write-Host "Waiting for Docker daemon..."

for ($i = 0; $i -lt 24; $i++) {
    Start-Sleep -Seconds 5
    try {
        $output = docker version --format '{{.Server.Version}}' 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Docker ready! Server version: $output"
            
            # Clean up corrupted state
            Write-Host "Pruning Docker..."
            docker system prune -af 2>&1 | Out-Null
            Write-Host "Done!"
            exit 0
        }
    } catch {}
    Write-Host "  attempt $($i+1)/24..."
}
Write-Host "Docker not ready after 120s"
exit 1
