$ErrorActionPreference = 'Continue'
Write-Host "=== docker/powershell processes ==="
Get-Process docker,powershell -ErrorAction SilentlyContinue | Select-Object Id,ProcessName,StartTime,@{N='RunMin';E={[math]::Round(((Get-Date)-$_.StartTime).TotalMinutes,1)}} | Format-Table -AutoSize | Out-String
Write-Host "=== buildkit disk activity proxy: vmmem CPU ==="
Get-Process | Where-Object {$_.ProcessName -match 'vmmem'} | Select-Object ProcessName,Id,CPU,@{N='WSMB';E={[math]::Round($_.WorkingSet64/1MB,0)}} | Format-Table -AutoSize | Out-String
Write-Host "=== docker buildx du (build cache size growing?) ==="
docker system df 2>&1
Write-Host "=== DONE ==="
