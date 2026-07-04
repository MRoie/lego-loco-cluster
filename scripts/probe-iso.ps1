docker exec loco-control-plane sh -c "ls -lh /opt/win98se.iso 2>/dev/null || echo not-yet"
Get-Process kubectl,docker -ErrorAction SilentlyContinue | Select-Object Id,ProcessName,StartTime
Write-Host "=== DONE ==="
