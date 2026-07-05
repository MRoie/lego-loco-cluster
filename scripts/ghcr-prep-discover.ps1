$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
$BinDir = Join-Path $RepoRoot ".bin"
Remove-Item Env:\KUBECONFIG -ErrorAction SilentlyContinue
Set-Location $RepoRoot
$Kube = "$BinDir\kubectl.exe"
$Pod = "loco-loco-emulator-0"

Write-Host "=== oras available? ==="
where.exe oras 2>&1
Get-ChildItem "$BinDir" -Filter "oras*" -ErrorAction SilentlyContinue

Write-Host "=== docker login status for ghcr.io ==="
docker system info 2>&1 | Select-String -Pattern "Registry|Username"
Get-Content "$env:USERPROFILE\.docker\config.json" -ErrorAction SilentlyContinue | Select-String "ghcr"

Write-Host "=== instance qcow2 details inside pod ==="
& $Kube exec $Pod -n loco -- sh -c "ls -lh /images/*.qcow2 /opt/builtin-images/*.builtin 2>&1" 2>&1

Write-Host "=== qemu-img present in emulator image? ==="
& $Kube exec $Pod -n loco -- sh -c "which qemu-img 2>&1; qemu-img --version 2>&1" 2>&1

Write-Host "=== DONE ==="
