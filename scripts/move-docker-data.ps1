# Move Docker Desktop data to R:\DockerData via junction link
# This ensures C: drive doesn't fill up with Docker images

$localDockerPath = Join-Path $env:LOCALAPPDATA "Docker\wsl"
$targetPath = "R:\DockerData\wsl"

Write-Host "=== Moving Docker data from C: to R: drive ==="

# Remove existing directory/junction if exists
if (Test-Path $localDockerPath) {
    $item = Get-Item $localDockerPath -Force
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        Write-Host "Removing existing junction at $localDockerPath"
        cmd /c "rmdir `"$localDockerPath`""
    } else {
        Write-Host "Removing existing directory at $localDockerPath"
        Remove-Item $localDockerPath -Recurse -Force
    }
}

# Ensure target exists
New-Item -ItemType Directory -Path $targetPath -Force | Out-Null

# Create junction
Write-Host "Creating junction: $localDockerPath -> $targetPath"
cmd /c "mklink /J `"$localDockerPath`" `"$targetPath`""

if (Test-Path $localDockerPath) {
    Write-Host "SUCCESS: Junction created"
    Write-Host "Docker data will now be stored on R: drive"
} else {
    Write-Host "FAILED: Junction not created"
}
