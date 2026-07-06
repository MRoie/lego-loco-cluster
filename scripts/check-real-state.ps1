$ErrorActionPreference = 'Continue'
Write-Host "=== all cmd.exe/powershell.exe processes with commandline ===" -ForegroundColor Cyan
Get-CimInstance Win32_Process | Where-Object { $_.Name -eq "cmd.exe" -or $_.Name -eq "powershell.exe" } | Select-Object ProcessId, CommandLine | Format-List

Write-Host "=== all docker.exe processes ===" -ForegroundColor Cyan
Get-CimInstance Win32_Process | Where-Object { $_.Name -like "docker*" } | Select-Object ProcessId, Name, CommandLine | Format-List

Write-Host "=== dir of .dockertemp ===" -ForegroundColor Cyan
Get-ChildItem "G:\dev\.dockertemp" -Force -ErrorAction SilentlyContinue

Write-Host "=== DONE ===" -ForegroundColor Green
