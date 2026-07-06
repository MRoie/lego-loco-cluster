$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
$BinDir = Join-Path $RepoRoot ".bin"
$env:PATH = "$BinDir;$env:PATH"
$env:KUBECONFIG = Join-Path $RepoRoot ".kube-config"
Set-Location $RepoRoot

Write-Host "=== Node capacity/allocatable ===" -ForegroundColor Cyan
& "$BinDir\kubectl.exe" describe node loco-control-plane | Select-String -Pattern "Capacity:|Allocatable:|cpu:|memory:|Non-terminated|Requests|Limits|--------" -Context 0,0

Write-Host "=== kubectl top nodes ===" -ForegroundColor Cyan
& "$BinDir\kubectl.exe" top nodes 2>&1

Write-Host "=== kubectl top pods -n loco ===" -ForegroundColor Cyan
& "$BinDir\kubectl.exe" top pods -n loco 2>&1

Write-Host "=== Emulator pod resource requests/limits ===" -ForegroundColor Cyan
& "$BinDir\kubectl.exe" get pods -n loco -l app.kubernetes.io/component=emulator -o jsonpath="{range .items[*]}{.metadata.name}{'\n'}{.spec.containers[0].resources}{'\n\n'}{end}"

Write-Host "=== Docker Desktop resource info (docker info) ===" -ForegroundColor Cyan
docker info --format "CPUs: {{.NCPU}}  Memory: {{.MemTotal}}"

Write-Host "=== Emulator QEMU launch command (checking for kvm/tcg) ===" -ForegroundColor Cyan
& "$BinDir\kubectl.exe" exec -n loco loco-loco-emulator-0 -- sh -c "ps aux | grep qemu | grep -v grep" 2>&1

Write-Host "=== WSL memory/cpu config (.wslconfig) ===" -ForegroundColor Cyan
$wslConfigPath = "$env:USERPROFILE\.wslconfig"
if (Test-Path $wslConfigPath) {
  Get-Content $wslConfigPath
} else {
  Write-Host "No .wslconfig found (using defaults: 50% of host RAM, all cores)"
}

Write-Host "=== Host CPU info ===" -ForegroundColor Cyan
Get-CimInstance -ClassName Win32_Processor | Select-Object Name, NumberOfCores, NumberOfLogicalProcessors
Get-CimInstance -ClassName Win32_ComputerSystem | Select-Object TotalPhysicalMemory

Write-Host "=== DONE ===" -ForegroundColor Green
