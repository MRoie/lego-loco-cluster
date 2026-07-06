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

Write-Host "=== Cleaning up old export container ===" -ForegroundColor Cyan
docker rm -f lantest-export 2>&1 | Out-Null

Write-Host "=== docker create ===" -ForegroundColor Cyan
docker create --name lantest-export lego-loco-emulator:lan-test
Write-Host "create exit code: $LASTEXITCODE"

Write-Host "=== docker export ===" -ForegroundColor Cyan
Write-Host "Start: $(Get-Date)"
docker export lantest-export -o "$TempOnG\lan-test-flat.tar"
Write-Host "export exit code: $LASTEXITCODE"
Write-Host "End: $(Get-Date)"

docker rm -f lantest-export 2>&1 | Out-Null

if ($LASTEXITCODE -eq 0 -or (Test-Path "$TempOnG\lan-test-flat.tar")) {
  Write-Host "=== docker import ===" -ForegroundColor Cyan
  Write-Host "Import start: $(Get-Date)"
  docker rmi -f lego-loco-emulator:lan-test-flat 2>&1 | Out-Null
  docker import --change "ENTRYPOINT [`"/entrypoint.sh`"]" "$TempOnG\lan-test-flat.tar" "lego-loco-emulator:lan-test-flat"
  Write-Host "import exit code: $LASTEXITCODE"
  Write-Host "Import end: $(Get-Date)"

  if ($LASTEXITCODE -eq 0) {
    Write-Host "=== Loading flattened image directly into kind (no separate save/verify step) ===" -ForegroundColor Cyan
    & "$BinDir\kind.exe" load docker-image lego-loco-emulator:lan-test-flat --name loco
    Write-Host "kind load exit code: $LASTEXITCODE"
  } else {
    Write-Host "docker import failed" -ForegroundColor Red
  }
} else {
  Write-Host "docker export failed, tar not found" -ForegroundColor Red
}

Write-Host "=== docker images ===" -ForegroundColor Cyan
docker images

Write-Host "=== DONE ===" -ForegroundColor Green
