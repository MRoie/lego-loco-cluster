$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
$BinDir = Join-Path $RepoRoot ".bin"
$env:PATH = "$BinDir;$env:PATH"
$env:KUBECONFIG = Join-Path $RepoRoot ".kube-config"
Set-Location $RepoRoot
$Kind = "$BinDir\kind.exe"
$Kube = "$BinDir\kubectl.exe"

# keep big temp tar on G: (Windows disk), not the Docker VM
$TempOnG = "G:\dev\.dockertemp"
Remove-Item "$TempOnG\*" -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $TempOnG -Force | Out-Null
$env:TEMP = $TempOnG; $env:TMP = $TempOnG

Write-Host "=== 1. (re)create kind cluster 'loco' [$(Get-Date -Format HH:mm:ss)] ==="
& $Kind delete cluster --name loco 2>&1 | Out-Null
& $Kind create cluster --name loco --wait 180s 2>&1 | Select-Object -Last 4
Write-Host "create exit: $LASTEXITCODE"
& $Kube get nodes 2>&1

Write-Host "=== 2. pull base win98-softgpu:latest [$(Get-Date -Format HH:mm:ss)] ==="
docker pull ghcr.io/mroie/lego-loco-cluster/win98-softgpu:latest 2>&1 | Select-Object -Last 3

Write-Host "=== 3. build network-patch emulator image [$(Get-Date -Format HH:mm:ss)] ==="
$env:DOCKER_BUILDKIT = "0"
docker build -f containers/qemu-softgpu/Dockerfile.patch-network -t lego-loco-emulator:lan-test containers/qemu-softgpu 2>&1 | Select-Object -Last 4
Write-Host "patch build exit: $LASTEXITCODE"
docker run --rm lego-loco-emulator:lan-test grep -c "ENABLE_GUEST_L2_MESH" /entrypoint.sh 2>&1

Write-Host "=== 4. flatten via export/import [$(Get-Date -Format HH:mm:ss)] ==="
docker rm -f lantest-export 2>&1 | Out-Null
docker create --name lantest-export lego-loco-emulator:lan-test 2>&1 | Out-Null
docker export lantest-export -o "$TempOnG\lan-test-flat.tar" 2>&1
Write-Host "export exit: $LASTEXITCODE ; tar size: $([math]::Round((Get-Item "$TempOnG\lan-test-flat.tar").Length/1MB,0)) MB"
docker rm -f lantest-export 2>&1 | Out-Null
docker rmi -f lego-loco-emulator:lan-test-flat 2>&1 | Out-Null
docker import --change 'ENTRYPOINT ["/entrypoint.sh"]' "$TempOnG\lan-test-flat.tar" "lego-loco-emulator:lan-test-flat" 2>&1
Write-Host "import exit: $LASTEXITCODE"

Write-Host "=== 5. kind load flattened emulator image [$(Get-Date -Format HH:mm:ss)] ==="
& $Kind load docker-image lego-loco-emulator:lan-test-flat --name loco 2>&1 | Select-Object -Last 3
Write-Host "kind load exit: $LASTEXITCODE"
Remove-Item "$TempOnG\lan-test-flat.tar" -Force -ErrorAction SilentlyContinue

Write-Host "=== DONE [$(Get-Date -Format HH:mm:ss)] ==="
