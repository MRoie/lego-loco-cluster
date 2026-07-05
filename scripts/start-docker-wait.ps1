# Start Docker Desktop and wait for daemon readiness  
Write-Host "Starting Docker Desktop..."
Start-Process "C:\Program Files\Docker\Docker\Docker Desktop.exe"
Write-Host "Waiting for Docker daemon to initialize (WSL distro creation may take 30-60s)..."

$maxAttempts = 40  # 200 seconds max
for ($i = 1; $i -le $maxAttempts; $i++) {
    Start-Sleep 5
    $elapsed = $i * 5
    Write-Host "  Attempt $i/$maxAttempts (${elapsed}s)..."
    
    $result = docker version --format "{{.Server.Version}}" 2>&1
    $exitCode = $LASTEXITCODE
    
    if ($exitCode -eq 0 -and $result -match '^\d+\.\d+') {
        Write-Host "`nDocker daemon is READY!"
        Write-Host "Server version: $result"
        Write-Host ""
        docker info 2>&1 | Select-Object -First 20
        Write-Host ""
        Write-Host "=== Disk check ==="
        $cFree = [math]::Round((Get-PSDrive C).Free / 1GB, 2)
        $rFree = [math]::Round((Get-PSDrive R).Free / 1GB, 2)
        Write-Host "C: drive free: $cFree GB"
        Write-Host "R: drive free: $rFree GB"
        exit 0
    }
}

Write-Host "`nERROR: Docker daemon did not start in $($maxAttempts * 5) seconds"
Write-Host "Last output: $result"
wsl -l -v 2>&1
exit 1
