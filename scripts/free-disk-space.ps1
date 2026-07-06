$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
$BinDir = Join-Path $RepoRoot ".bin"
$env:PATH = "$BinDir;$env:PATH"
$env:KUBECONFIG = Join-Path $RepoRoot ".kube-config"
Set-Location $RepoRoot

Write-Host "=== Disk free before ===" -ForegroundColor Cyan
Get-PSDrive C | Select-Object Used,Free

Write-Host "=== docker system df before ===" -ForegroundColor Cyan
docker system df

Write-Host "=== Pruning dangling images ===" -ForegroundColor Cyan
docker image prune -f

Write-Host "=== Removing known-superseded large images ===" -ForegroundColor Cyan
# Old intermediate/duplicate win98 build layers no longer needed now that
# win98-softgpu:latest (published) and lan-test patch are the ones we use.
$toRemove = @(
  "4ca44a328aa2",
  "143fdb6c5788",
  "707478a2926d",
  "98aa678579a0",
  "00aaa7681db4",
  "cec2ffda8fff",
  "9adeaf0a7a48",
  "29e4ce01eee5",
  "c504ff900c44",
  "win98-rebuild-local:latest",
  "win98-softgpu-local:latest",
  "qemu-interactive:latest",
  "4006995c00f0"
)
foreach ($img in $toRemove) {
  Write-Host "Removing $img ..."
  docker rmi -f $img 2>&1 | Out-String | Write-Host
}

Write-Host "=== docker system df after ===" -ForegroundColor Cyan
docker system df

Write-Host "=== Disk free after ===" -ForegroundColor Cyan
Get-PSDrive C | Select-Object Used,Free

Write-Host "=== docker images (remaining) ===" -ForegroundColor Cyan
docker images

Write-Host "=== DONE ===" -ForegroundColor Green
