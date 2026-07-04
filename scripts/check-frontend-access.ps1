$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
$BinDir = Join-Path $RepoRoot ".bin"
$env:PATH = "$BinDir;$env:PATH"
$env:KUBECONFIG = Join-Path $RepoRoot ".kube-config"
Set-Location $RepoRoot

Write-Host "=== Pods ===" -ForegroundColor Cyan
& "$BinDir\kubectl.exe" get pods -n loco -o wide

Write-Host "=== Services ===" -ForegroundColor Cyan
& "$BinDir\kubectl.exe" get svc -n loco

Write-Host "=== Existing port-forward processes ===" -ForegroundColor Cyan
Get-Process | Where-Object { $_.ProcessName -eq 'kubectl' } | Select-Object Id, ProcessName, StartTime

Write-Host "=== Netstat for port 3000 ===" -ForegroundColor Cyan
netstat -ano | findstr ":3000"

Write-Host "=== DONE ===" -ForegroundColor Green
