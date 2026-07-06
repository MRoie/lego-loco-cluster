$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
$BinDir = Join-Path $RepoRoot ".bin"
$env:PATH = "$BinDir;$env:PATH"
$env:KUBECONFIG = Join-Path $RepoRoot ".kube-config"
Set-Location $RepoRoot

$TempOnG = "G:\dev\.dockertemp"
Remove-Item "$TempOnG\*" -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $TempOnG -Force | Out-Null
$env:TEMP = $TempOnG
$env:TMP = $TempOnG

Write-Host "=== docker save appears hung on this image (broken export path post-crash) ===" -ForegroundColor Yellow
Write-Host "Working around via: docker create -> docker export (container-level, bypasses image-layer save) -> docker import (fresh single-layer image) -> kind load" -ForegroundColor Yellow

Write-Host "=== Removing any leftover export container ===" -ForegroundColor Cyan
docker rm -f lantest-export 2>&1 | Out-Null

Write-Host "=== docker create (no entrypoint execution) ===" -ForegroundColor Cyan
docker create --name lantest-export lego-loco-emulator:lan-test
Write-Host "create exit code: $LASTEXITCODE"

Write-Host "=== docker export to $TempOnG\lan-test-flat.tar ===" -ForegroundColor Cyan
Write-Host "Start: $(Get-Date)"
docker export lantest-export -o "$TempOnG\lan-test-flat.tar"
Write-Host "export exit code: $LASTEXITCODE"
Write-Host "End: $(Get-Date)"

if ($LASTEXITCODE -eq 0) {
  Write-Host "=== Tar file size ===" -ForegroundColor Cyan
  Get-Item "$TempOnG\lan-test-flat.tar" | Select-Object Name,Length

  Write-Host "=== docker import (create fresh flattened image) ===" -ForegroundColor Cyan
  docker import --change "ENTRYPOINT [`"/entrypoint.sh`"]" "$TempOnG\lan-test-flat.tar" "lego-loco-emulator:lan-test-flat"
  Write-Host "import exit code: $LASTEXITCODE"

  docker rm -f lantest-export 2>&1 | Out-Null

  Write-Host "=== docker save the FRESH flattened image (test if save works now) ===" -ForegroundColor Cyan
  docker save -o "$TempOnG\flat-verify.tar" lego-loco-emulator:lan-test-flat
  Write-Host "save exit code: $LASTEXITCODE"

  if ($LASTEXITCODE -eq 0) {
    Remove-Item "$TempOnG\flat-verify.tar" -Force -ErrorAction SilentlyContinue
    Write-Host "=== Loading flattened image into kind ===" -ForegroundColor Cyan
    & "$BinDir\kind.exe" load docker-image lego-loco-emulator:lan-test-flat --name loco
    Write-Host "kind load exit code: $LASTEXITCODE"
  } else {
    Write-Host "docker save STILL hangs/fails even on flattened image - engine-level problem" -ForegroundColor Red
  }
} else {
  docker rm -f lantest-export 2>&1 | Out-Null
  Write-Host "docker export failed too - deeper problem" -ForegroundColor Red
}

Write-Host "=== DONE ===" -ForegroundColor Green
