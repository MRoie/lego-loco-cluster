$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
$BinDir = Join-Path $RepoRoot ".bin"
$env:PATH = "$BinDir;$env:PATH"
$env:KUBECONFIG = Join-Path $RepoRoot ".kube-config"
Set-Location $RepoRoot

$TempOnG = "G:\dev\.dockertemp"
Remove-Item "$TempOnG\*" -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $TempOnG -Force | Out-Null
$env:TEMP = $TempOnG
$env:TMP = $TempOnG

Write-Host "TEMP redirected to: $env:TEMP" -ForegroundColor Cyan
Write-Host "Start time: $(Get-Date)" -ForegroundColor Cyan

Write-Host "=== Loading lego-loco-emulator:lan-test into kind directly ===" -ForegroundColor Cyan
& "$BinDir\kind.exe" load docker-image lego-loco-emulator:lan-test --name loco
Write-Host "kind load exit code: $LASTEXITCODE"
Write-Host "End time: $(Get-Date)" -ForegroundColor Cyan

Write-Host "=== DONE ===" -ForegroundColor Green
