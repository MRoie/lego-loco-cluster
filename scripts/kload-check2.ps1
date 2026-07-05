$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
Write-Host "=== now ==="
Get-Date
Write-Host "=== kind/docker/powershell processes ==="
Get-Process kind,docker,powershell -ErrorAction SilentlyContinue |
  Select-Object Id,ProcessName,StartTime,CPU,@{N='RunningMin';E={[math]::Round(((Get-Date)-$_.StartTime).TotalMinutes,1)}} |
  Sort-Object StartTime | Format-Table -AutoSize | Out-String -Width 200
Write-Host "=== kind clusters ==="
& "$RepoRoot\.bin\kind.exe" get clusters 2>&1
Write-Host "=== containerd images on node (is the load actually landing?) ==="
docker exec loco-control-plane crictl images 2>&1
Write-Host "=== docker images on host (flat tar present?) ==="
docker images 2>&1 | Select-String "lan-test|emulator"
Write-Host "=== .dockertemp tar size (is it done being written / stable?) ==="
Get-ChildItem "G:\dev\.dockertemp" -ErrorAction SilentlyContinue | Select-Object Name,Length,LastWriteTime | Format-Table -AutoSize | Out-String
Write-Host "=== docker desktop / wsl vmmem CPU (is anything actually churning?) ==="
Get-Process vmmem,vmmemWSL,com.docker.backend -ErrorAction SilentlyContinue | Select-Object Id,ProcessName,CPU,WorkingSet64 | Format-Table -AutoSize | Out-String
Write-Host "=== DONE ==="
