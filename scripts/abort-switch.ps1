$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
$BinDir = Join-Path $RepoRoot ".bin"
$env:PATH = "$BinDir;$env:PATH"
Set-Location $RepoRoot

Write-Host "=== 1. abort stuck kind-load (clean kill, no force-corrupt) ==="
# kill kind orchestrator + its docker save child by image name (safe process kill)
taskkill /IM kind.exe /F 2>&1
# the rebuild1 powershell parent (started ~8:59) is blocked on the load; stop it too
Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match 'rebuild1-emulator-image\.ps1' } | ForEach-Object { Write-Host "killing rebuild1 ps $($_.ProcessId)"; Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
# kill the specific docker save that kind spawned (image stream), if still around
Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'docker.exe' -and $_.CommandLine -match 'save' } | ForEach-Object { Write-Host "killing docker save $($_.ProcessId)"; Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Start-Sleep -Seconds 2
Write-Host "kind/docker-save still running?"
Get-Process kind -ErrorAction SilentlyContinue | Select-Object Id,ProcessName

Write-Host "=== 2. Docker Desktop built-in Kubernetes status ==="
& "$BinDir\kubectl.exe" config get-contexts 2>&1
Write-Host "--- nodes on docker-desktop context ---"
& "$BinDir\kubectl.exe" --context docker-desktop get nodes --request-timeout=10s 2>&1

Write-Host "=== 3. local images available for in-cluster use (no load needed) ==="
docker images --format "{{.Repository}}:{{.Tag}}  {{.Size}}" 2>&1 | Select-String "lego-loco|win98-softgpu|backend|frontend"

Write-Host "=== DONE ==="
