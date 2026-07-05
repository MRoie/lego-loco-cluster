$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
$BinDir = Join-Path $RepoRoot ".bin"
$env:PATH = "$BinDir;$env:PATH"
$env:KUBECONFIG = Join-Path $RepoRoot ".kube-config"
Write-Host "=== kubectl get nodes (10s client timeout) ==="
& "$BinDir\kubectl.exe" get nodes --request-timeout=10s 2>&1
Write-Host "=== current-context ==="
& "$BinDir\kubectl.exe" config current-context 2>&1
Write-Host "=== win98 base pulled? ==="
docker images 2>&1 | Select-String "win98-softgpu|lego-loco-emulator"
Write-Host "=== running powershell/kind processes ==="
Get-Process powershell,kind,docker -ErrorAction SilentlyContinue | Select-Object Id,ProcessName,StartTime | Format-Table -AutoSize | Out-String
Write-Host "=== DONE ==="
