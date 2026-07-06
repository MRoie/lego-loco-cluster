$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
$BinDir = Join-Path $RepoRoot ".bin"
$env:PATH = "$BinDir;$env:PATH"
$env:KUBECONFIG = Join-Path $RepoRoot ".kube-config"
Set-Location $RepoRoot

# Redirect temp dir to G: (332GB free) instead of C: (~9GB free) since
# `kind load docker-image` shells out to `docker save` which needs a temp
# tar roughly the size of the image (9.6GB) - too tight on C:.
$TempOnG = "G:\dev\.dockertemp"
New-Item -ItemType Directory -Path $TempOnG -Force | Out-Null
$env:TEMP = $TempOnG
$env:TMP = $TempOnG

Write-Host "TEMP redirected to: $env:TEMP" -ForegroundColor Cyan

Write-Host "=== docker save verify (to G: temp) ===" -ForegroundColor Cyan
docker save -o "$TempOnG\lan-test-verify.tar" lego-loco-emulator:lan-test
Write-Host "docker save exit code: $LASTEXITCODE"

if ($LASTEXITCODE -eq 0) {
  Remove-Item "$TempOnG\lan-test-verify.tar" -Force -ErrorAction SilentlyContinue
  Write-Host "=== Loading into kind (retry, TEMP on G:) ===" -ForegroundColor Cyan
  & "$BinDir\kind.exe" load docker-image lego-loco-emulator:lan-test --name loco
  Write-Host "kind load exit code: $LASTEXITCODE"
} else {
  Write-Host "docker save STILL failing - deeper problem" -ForegroundColor Red
}

Write-Host "=== DONE ===" -ForegroundColor Green
