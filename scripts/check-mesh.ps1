$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
$BinDir = Join-Path $RepoRoot ".bin"
$env:PATH = "$BinDir;$env:PATH"
$env:KUBECONFIG = Join-Path $RepoRoot ".kube-config"
Set-Location $RepoRoot

Write-Host "=== emulator-0: mesh/dhcp/vxlan lines ===" -ForegroundColor Cyan
& "$BinDir\kubectl.exe" logs loco-loco-emulator-0 -n loco | Select-String -Pattern "VXLAN|mesh|DHCP|vxlan"

Write-Host "=== emulator-1: mesh/dhcp/vxlan lines ===" -ForegroundColor Cyan
& "$BinDir\kubectl.exe" logs loco-loco-emulator-1 -n loco | Select-String -Pattern "VXLAN|mesh|DHCP|vxlan"

Write-Host "=== emulator-0: ip link + bridge fdb (vxlan peers) ===" -ForegroundColor Cyan
& "$BinDir\kubectl.exe" exec loco-loco-emulator-0 -n loco -- ip link show
& "$BinDir\kubectl.exe" exec loco-loco-emulator-0 -n loco -- bridge fdb show dev vxlan0

Write-Host "=== emulator-1: ip link + bridge fdb (vxlan peers) ===" -ForegroundColor Cyan
& "$BinDir\kubectl.exe" exec loco-loco-emulator-1 -n loco -- ip link show
& "$BinDir\kubectl.exe" exec loco-loco-emulator-1 -n loco -- bridge fdb show dev vxlan1

Write-Host "=== DONE ===" -ForegroundColor Green
