$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
$BinDir = Join-Path $RepoRoot ".bin"
$env:PATH = "$BinDir;$env:PATH"
$env:KUBECONFIG = Join-Path $RepoRoot ".kube-config"
Set-Location $RepoRoot
$Kube = "$BinDir\kubectl.exe"

foreach ($i in 0,1) {
  $pod = "loco-loco-emulator-$i"
  Write-Host "### $pod ###"
  Write-Host "--- pulseaudio processes ---"
  & $Kube exec $pod -n loco -- sh -c "pgrep -a pulseaudio || echo NO-PULSE" 2>&1
  Write-Host "--- qemu thread states (D/S) ---"
  & $Kube exec $pod -n loco -- sh -c "q=`$(pgrep -fo qemu-system); cat /proc/`$q/status | grep -E 'State|Threads'; for t in /proc/`$q/task/*; do s=`$(grep State `$t/status | awk '{print `$2}'); n=`$(cat `$t/comm); echo `$n `$s; done" 2>&1
  Write-Host "--- restart pulseaudio ---"
  & $Kube exec $pod -n loco -- sh -c "pkill -9 pulseaudio; sleep 1; pulseaudio --start --exit-idle-time=-1 2>&1; pgrep -a pulseaudio" 2>&1
}
Write-Host "=== DONE ==="
