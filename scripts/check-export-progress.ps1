$ErrorActionPreference = 'Continue'
Write-Host "=== tar file size (if exists) ===" -ForegroundColor Cyan
$path = "G:\dev\.dockertemp\lan-test-flat.tar"
if (Test-Path $path) {
  Get-Item $path | Select-Object Name, Length, LastWriteTime
} else {
  Write-Host "tar file not yet created"
}

Write-Host "=== docker processes on host (Get-Process docker*) ===" -ForegroundColor Cyan
Get-Process | Where-Object { $_.Name -like "*docker*" -or $_.Name -like "*com.docker*" } | Select-Object Name, Id, CPU

Write-Host "=== docker ps -a ===" -ForegroundColor Cyan
docker ps -a

Write-Host "=== DONE ===" -ForegroundColor Green
