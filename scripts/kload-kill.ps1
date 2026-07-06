$ErrorActionPreference = 'Continue'
Write-Host "=== target process before kill ==="
Get-Process -Id 21056 -ErrorAction SilentlyContinue | Select-Object Id,ProcessName,StartTime,Path | Format-List | Out-String

$p = Get-Process -Id 21056 -ErrorAction SilentlyContinue
if ($p) {
    Write-Host "Stopping PID 21056 (plain Stop-Process, no -Force)..."
    Stop-Process -Id 21056 -ErrorAction Continue
    Start-Sleep -Seconds 3
    $still = Get-Process -Id 21056 -ErrorAction SilentlyContinue
    if ($still) {
        Write-Host "Still alive after plain stop, escalating to -Force..."
        Stop-Process -Id 21056 -Force -ErrorAction Continue
        Start-Sleep -Seconds 2
    }
} else {
    Write-Host "PID 21056 not found (already gone)."
}

Write-Host "=== also clearing the now-hung diagnostic script (kload-check2) if still stuck ==="
Get-Process powershell -ErrorAction SilentlyContinue |
  Where-Object { $_.Id -eq 21004 } |
  ForEach-Object {
    Write-Host "Stopping hung diagnostic PowerShell PID $($_.Id)..."
    Stop-Process -Id $_.Id -Force -ErrorAction Continue
  }

Start-Sleep -Seconds 2
Write-Host "=== remaining kind/docker/powershell processes ==="
Get-Process kind,docker,powershell -ErrorAction SilentlyContinue |
  Select-Object Id,ProcessName,StartTime | Format-Table -AutoSize | Out-String

Write-Host "=== docker daemon responsiveness check (docker info, should return quickly now) ==="
$sw = [System.Diagnostics.Stopwatch]::StartNew()
docker info --format '{{.ServerVersion}}' 2>&1
$sw.Stop()
Write-Host "docker info took $($sw.Elapsed.TotalSeconds) sec"

Write-Host "=== memory snapshot ==="
Get-Process | Where-Object {$_.ProcessName -match 'vmmem|Vmmem'} | Select-Object ProcessName,Id,@{N='WorkingSetMB';E={[math]::Round($_.WorkingSet64/1MB,0)}} | Format-Table -AutoSize | Out-String

Write-Host "=== DONE ==="
