$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
$BinDir = Join-Path $RepoRoot ".bin"
Write-Host "=== node containerd images (emulator loaded?) ==="
docker exec loco-control-plane crictl images 2>&1 | Select-String "emulator|lan-test|backend|frontend"
Write-Host "=== kind/docker save processes running? ==="
Get-Process kind,docker -ErrorAction SilentlyContinue | Select-Object Id,ProcessName,StartTime | Format-Table -AutoSize | Out-String
Write-Host "=== node disk ==="
docker exec loco-control-plane sh -c "df -h / 2>&1" 2>&1
Write-Host "=== rebuild1 powershell still alive? (started 8:59) ==="
Get-Process powershell -ErrorAction SilentlyContinue | Select-Object Id,StartTime | Format-Table -AutoSize | Out-String
Write-Host "=== DONE ==="
