$ErrorActionPreference = 'Continue'
Write-Host "=== simple docker ps (fresh, should be instant if daemon healthy) ===" -ForegroundColor Cyan
$start = Get-Date
docker ps
$elapsed = (Get-Date) - $start
Write-Host "Elapsed: $($elapsed.TotalSeconds) seconds"

Write-Host "=== docker version (checks daemon RPC) ===" -ForegroundColor Cyan
$start2 = Get-Date
docker version --format "{{.Server.Version}}"
$elapsed2 = (Get-Date) - $start2
Write-Host "Elapsed: $($elapsed2.TotalSeconds) seconds"

Write-Host "=== DONE ===" -ForegroundColor Green
