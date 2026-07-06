$ErrorActionPreference = 'Continue'
Write-Host "=== Killing stuck docker/kind CLI processes ===" -ForegroundColor Cyan
Get-Process docker -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "Killing docker PID $($_.Id)"; Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue }
Get-Process kind -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "Killing kind PID $($_.Id)"; Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue }
Write-Host "=== Remaining docker/kind processes ===" -ForegroundColor Cyan
Get-Process docker,kind -ErrorAction SilentlyContinue
Write-Host "=== DONE ===" -ForegroundColor Green
