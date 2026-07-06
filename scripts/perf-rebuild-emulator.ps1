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

Write-Host "=== Step 1: Building network-patched emulator image with WebRTC-disabled entrypoint ===" -ForegroundColor Cyan
docker build -f containers/qemu-softgpu/Dockerfile.patch-network -t lego-loco-emulator:lan-test containers/qemu-softgpu
$buildExit = $LASTEXITCODE
Write-Host "Build exit code: $buildExit"

if ($buildExit -ne 0) {
  Write-Host "Build failed, aborting" -ForegroundColor Red
  exit 1
}

Write-Host "=== Verify ENABLE_WEBRTC_STREAM gate present ===" -ForegroundColor Cyan
docker run --rm lego-loco-emulator:lan-test grep -c "ENABLE_WEBRTC_STREAM" /entrypoint.sh

Write-Host "=== Step 2: Flatten image (export/import) to match deployed lan-test-flat lineage ===" -ForegroundColor Cyan
docker rm -f lantest-export 2>&1 | Out-Null
docker create --name lantest-export lego-loco-emulator:lan-test
docker export lantest-export -o "$TempOnG\lan-test-flat.tar"
Write-Host "export exit code: $LASTEXITCODE"
docker rm -f lantest-export 2>&1 | Out-Null

docker rmi -f lego-loco-emulator:lan-test-flat 2>&1 | Out-Null
docker import --change "ENTRYPOINT [`"/entrypoint.sh`"]" "$TempOnG\lan-test-flat.tar" "lego-loco-emulator:lan-test-flat"
$importExit = $LASTEXITCODE
Write-Host "import exit code: $importExit"

if ($importExit -ne 0) {
  Write-Host "Flatten/import failed, aborting" -ForegroundColor Red
  exit 1
}

Write-Host "=== Step 3: Load into kind ===" -ForegroundColor Cyan
& "$BinDir\kind.exe" load docker-image lego-loco-emulator:lan-test-flat --name loco

Write-Host "=== Step 4: helm upgrade (applies bumped CPU limit) ===" -ForegroundColor Cyan
& "$BinDir\helm.exe" upgrade --install loco helm/loco-chart -n loco -f helm/loco-chart/values-lan-test.yaml --timeout 5m
& "$BinDir\kubectl.exe" scale deployment/loco-loco-vr -n loco --replicas=0 2>&1 | Out-Null

Write-Host "=== Step 5: Restart emulator statefulset (both instances) ===" -ForegroundColor Cyan
& "$BinDir\kubectl.exe" rollout restart statefulset/loco-loco-emulator -n loco

Write-Host "=== Waiting 60s then checking pod status ===" -ForegroundColor Cyan
Start-Sleep -Seconds 60
& "$BinDir\kubectl.exe" get pods -n loco -o wide

Write-Host "=== DONE ===" -ForegroundColor Green
