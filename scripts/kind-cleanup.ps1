$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
$BinDir = Join-Path $RepoRoot ".bin"

Write-Host "=== kind clusters before ==="
& "$BinDir\kind.exe" get clusters 2>&1

Write-Host "=== deleting kind cluster 'loco' to free memory/CPU while we validate on Docker Desktop K8s ==="
& "$BinDir\kind.exe" delete cluster --name loco 2>&1

Write-Host "=== kind clusters after ==="
& "$BinDir\kind.exe" get clusters 2>&1

Write-Host "=== docker ps after cleanup ==="
docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Image}}" 2>&1

Write-Host "=== vmmem memory now ==="
Get-Process | Where-Object {$_.ProcessName -match 'vmmem'} | Select-Object ProcessName,Id,@{N='WorkingSetMB';E={[math]::Round($_.WorkingSet64/1MB,0)}} | Format-Table -AutoSize | Out-String

Write-Host "=== DONE ==="
