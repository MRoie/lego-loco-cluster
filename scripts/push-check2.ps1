$ErrorActionPreference = 'Continue'
Get-Process docker,powershell -ErrorAction SilentlyContinue | Select-Object Id,ProcessName,StartTime,@{N='RunMin';E={[math]::Round(((Get-Date)-$_.StartTime).TotalMinutes,1)}} | Format-Table -AutoSize | Out-String
Write-Host "=== DONE ==="
