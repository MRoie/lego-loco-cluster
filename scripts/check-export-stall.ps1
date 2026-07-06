$ErrorActionPreference = 'Continue'
Write-Host "=== G: drive free space ===" -ForegroundColor Cyan
Get-PSDrive G | Select-Object Used, Free

Write-Host "=== temp file details ===" -ForegroundColor Cyan
Get-Item "G:\dev\.dockertemp\.docker_temp_*" -ErrorAction SilentlyContinue | Select-Object Name, Length, LastWriteTime

Write-Host "=== is any 'docker export' cli process actually running? ===" -ForegroundColor Cyan
Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -like "*export*" } | Select-Object ProcessId, CommandLine

Write-Host "=== all docker.exe / docker cli processes with commandline ===" -ForegroundColor Cyan
Get-CimInstance Win32_Process | Where-Object { $_.Name -eq "docker.exe" } | Select-Object ProcessId, CommandLine

Write-Host "=== container inspect state (lantest-export) ===" -ForegroundColor Cyan
docker inspect lantest-export --format "{{.State.Status}}"

Write-Host "=== DONE ===" -ForegroundColor Green
