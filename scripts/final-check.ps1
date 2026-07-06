$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
$BinDir = Join-Path $RepoRoot ".bin"
Remove-Item Env:\KUBECONFIG -ErrorAction SilentlyContinue
Set-Location $RepoRoot
$Kube = "$BinDir\kubectl.exe"
$Pod = "loco-loco-emulator-0"
New-Item -ItemType Directory -Force -Path "scripts\out" | Out-Null

Write-Host "=== pods ==="
& $Kube get pods -n loco -o wide --request-timeout=15s 2>&1

Write-Host "=== final screendump (VM resumed and running?) ==="
& $Kube exec $Pod -n loco -- python3 /usr/local/bin/qmp-control.py screendump /tmp/final.ppm 2>&1
& $Kube cp -n loco "${Pod}:tmp/final.ppm" "scripts/out/final.ppm" 2>&1

Write-Host "=== kind cleanup status (still running in background?) ==="
Get-Process kind -ErrorAction SilentlyContinue | Select-Object Id,ProcessName,StartTime
docker ps -a --filter "name=loco-control-plane" --format "{{.Names}} {{.Status}}" 2>&1

Write-Host "=== memory ==="
Get-Process | Where-Object {$_.ProcessName -match 'vmmem'} | Select-Object ProcessName,Id,@{N='WSMB';E={[math]::Round($_.WorkingSet64/1MB,0)}} | Format-Table -AutoSize | Out-String

Write-Host "=== DONE ==="
