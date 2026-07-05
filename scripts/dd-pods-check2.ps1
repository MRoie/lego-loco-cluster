$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
$BinDir = Join-Path $RepoRoot ".bin"
Remove-Item Env:\KUBECONFIG -ErrorAction SilentlyContinue
$Kube = "$BinDir\kubectl.exe"

Write-Host "=== stuck processes? ==="
Get-Process kubectl,powershell -ErrorAction SilentlyContinue | Select-Object Id,ProcessName,StartTime | Format-Table -AutoSize | Out-String

Write-Host "=== pods (plain, short timeout) ==="
& $Kube get pods -n loco -o wide --request-timeout=10s 2>&1

Write-Host "=== docker ps (ground truth, bypass kube API) ==="
docker ps -a --filter "name=loco" --format "table {{.Names}}\t{{.Status}}\t{{.Image}}" 2>&1

Write-Host "=== DONE ==="
