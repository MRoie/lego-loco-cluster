$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
$BinDir = Join-Path $RepoRoot ".bin"
$env:PATH = "$BinDir;$env:PATH"
$env:KUBECONFIG = Join-Path $RepoRoot ".kube-config"
Set-Location $RepoRoot
$Kube = "$BinDir\kubectl.exe"

Write-Host "=== docker daemon ==="
docker version --format "server {{.Server.Version}}" 2>&1 | Select-Object -First 1
Write-Host "=== kind node ==="
docker ps -a --format "{{.Names}}  {{.Status}}" 2>&1 | Select-String "control-plane"
Write-Host "=== node filesystem writable test ==="
docker exec loco-control-plane sh -c "touch /var/lib/rwtest 2>&1 && echo WRITABLE && rm -f /var/lib/rwtest || echo READ-ONLY" 2>&1
Write-Host "=== node df ==="
docker exec loco-control-plane sh -c "df -h / /var 2>&1" 2>&1
Write-Host "=== dmesg tail (fs errors?) ==="
docker exec loco-control-plane sh -c "dmesg 2>/dev/null | tail -8 || echo no-dmesg" 2>&1
Write-Host "=== api server ==="
& $Kube get --raw='/readyz' 2>&1
Write-Host ""
& $Kube get pods -n loco 2>&1 | Select-Object -First 8
Write-Host "=== DONE ==="
