$ErrorActionPreference = 'Continue'
Write-Host "=== docker/powershell procs (is push script still alive?) ==="
Get-Process docker,powershell -ErrorAction SilentlyContinue | Select-Object Id,ProcessName,StartTime,@{N='RunMin';E={[math]::Round(((Get-Date)-$_.StartTime).TotalMinutes,1)}} | Format-Table -AutoSize | Out-String
Write-Host "=== network bytes sent (docker desktop backend) - rough proxy for upload progress ==="
Get-Process | Where-Object {$_.ProcessName -match 'com.docker.backend|docker'} | Select-Object ProcessName,Id | Format-Table -AutoSize | Out-String
Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue | Where-Object {$_.RemotePort -eq 443} | Select-Object -First 10 LocalPort,RemoteAddress,RemotePort | Format-Table -AutoSize | Out-String
Write-Host "=== DONE ==="
