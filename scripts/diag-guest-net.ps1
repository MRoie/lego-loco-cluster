$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
$BinDir = Join-Path $RepoRoot ".bin"
$env:PATH = "$BinDir;$env:PATH"
$env:KUBECONFIG = Join-Path $RepoRoot ".kube-config"
Set-Location $RepoRoot
$K = "$BinDir\kubectl.exe"

foreach ($i in 0,1) {
  $pod = "loco-loco-emulator-$i"
  Write-Host "########## $pod ##########" -ForegroundColor Cyan

  Write-Host "=== QEMU command line ===" -ForegroundColor Cyan
  & $K exec $pod -n loco -- sh -c "tr '\0' ' ' < /proc/`$(pgrep -f qemu-system | head -1)/cmdline; echo" 2>&1

  Write-Host "=== tap$i packet counters (rx = from guest) ===" -ForegroundColor Cyan
  & $K exec $pod -n loco -- sh -c "for f in rx_packets tx_packets rx_bytes tx_bytes; do echo -n `"tap${i} `$f: `"; cat /sys/class/net/tap$i/statistics/`$f; done" 2>&1

  Write-Host "=== identity floppy / DHCP log lines ===" -ForegroundColor Cyan
  & $K logs $pod -n loco 2>&1 | Select-String -Pattern "floppy|identity|Identity|DHCP|dhcp" | Select-Object -First 15

  Write-Host "=== DHCP server process (instance-0 only expected) ===" -ForegroundColor Cyan
  & $K exec $pod -n loco -- sh -c "pgrep -af mini_dhcp || echo no-mini-dhcp" 2>&1

  Write-Host "=== recent DHCP activity in logs ===" -ForegroundColor Cyan
  & $K logs $pod -n loco --tail=2000 2>&1 | Select-String -Pattern "DISCOVER|OFFER|REQUEST|ACK|dhcp" | Select-Object -Last 10
}
Write-Host "=== DONE ===" -ForegroundColor Green
