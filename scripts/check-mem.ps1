$ErrorActionPreference = 'Continue'
Write-Host "=== Memory ===" -ForegroundColor Cyan
Get-CimInstance Win32_OperatingSystem | Select-Object @{n='TotalGB';e={[math]::Round($_.TotalVisibleMemorySize/1MB,2)}}, @{n='FreeGB';e={[math]::Round($_.FreePhysicalMemory/1MB,2)}}

Write-Host "=== Top memory processes ===" -ForegroundColor Cyan
Get-Process | Sort-Object WorkingSet -Descending | Select-Object -First 15 Id, ProcessName, @{n='MemMB';e={[math]::Round($_.WorkingSet/1MB,1)}} | Format-Table -AutoSize

Write-Host "=== Chrome process count ===" -ForegroundColor Cyan
(Get-Process chrome -ErrorAction SilentlyContinue).Count

Write-Host "=== DONE ===" -ForegroundColor Green
