$ErrorActionPreference = 'Continue'
Write-Host "=== kind/docker/powershell procs ==="
Get-Process kind,docker,powershell -ErrorAction SilentlyContinue | Select-Object Id,ProcessName,StartTime,@{N='RunMin';E={[math]::Round(((Get-Date)-$_.StartTime).TotalMinutes,1)}} | Format-Table -AutoSize | Out-String
Write-Host "=== docker info timing ==="
$sw=[System.Diagnostics.Stopwatch]::StartNew()
docker info --format '{{.ServerVersion}}' 2>&1
Write-Host "took $($sw.Elapsed.TotalSeconds)s"
Write-Host "=== memory ==="
Get-Process | Where-Object {$_.ProcessName -match 'vmmem'} | Select-Object ProcessName,Id,@{N='WSMB';E={[math]::Round($_.WorkingSet64/1MB,0)}} | Format-Table -AutoSize | Out-String
Write-Host "=== docker ps loco-control-plane ==="
docker ps -a --filter "name=loco-control-plane" --format "{{.Names}} {{.Status}}" 2>&1
Write-Host "=== DONE ==="
