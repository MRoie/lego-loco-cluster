$ErrorActionPreference = 'Continue'
Write-Host "=== Top CPU processes ===" -ForegroundColor Cyan
Get-Process | Sort-Object CPU -Descending | Select-Object -First 15 Id, ProcessName, CPU, WorkingSet | Format-Table -AutoSize

Write-Host "=== Overall CPU load ===" -ForegroundColor Cyan
Get-CimInstance Win32_Processor | Select-Object LoadPercentage

Write-Host "=== DONE ===" -ForegroundColor Green
