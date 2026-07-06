$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
$BinDir = Join-Path $RepoRoot ".bin"
$env:PATH = "$BinDir;$env:PATH"
$env:KUBECONFIG = Join-Path $RepoRoot ".kube-config"
Set-Location $RepoRoot

Write-Host "=== docker ps -a (looking for stray verification container) ===" -ForegroundColor Cyan
docker ps -a

Write-Host "=== Removing any stopped containers from lego-loco-emulator:lan-test ===" -ForegroundColor Cyan
docker ps -a --filter "ancestor=lego-loco-emulator:lan-test" -q | ForEach-Object { docker rm -f $_ }

Write-Host "=== docker system df ===" -ForegroundColor Cyan
docker system df

Write-Host "=== Retry: docker save to verify readability ===" -ForegroundColor Cyan
docker save -o "$env:TEMP\lan-test-verify.tar" lego-loco-emulator:lan-test
Write-Host "docker save exit code: $LASTEXITCODE"

if ($LASTEXITCODE -eq 0) {
  Remove-Item "$env:TEMP\lan-test-verify.tar" -Force -ErrorAction SilentlyContinue
  Write-Host "=== Loading into kind (retry) ===" -ForegroundColor Cyan
  & "$BinDir\kind.exe" load docker-image lego-loco-emulator:lan-test --name loco
  Write-Host "kind load exit code: $LASTEXITCODE"
} else {
  Write-Host "docker save still failing - image layer likely corrupted, will need rebuild" -ForegroundColor Red
}

Write-Host "=== DONE ===" -ForegroundColor Green
