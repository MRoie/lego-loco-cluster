$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
$BinDir = Join-Path $RepoRoot ".bin"
$env:PATH = "$BinDir;$env:PATH"
$env:KUBECONFIG = Join-Path $RepoRoot ".kube-config"
Set-Location $RepoRoot
$Kube = "$BinDir\kubectl.exe"
New-Item -ItemType Directory -Force -Path "scripts\out" | Out-Null

# Steps file: each line = <podIndex> <cmd> <arg>
# cmds: key <keyname> | sleep <seconds> | dump <name> | hmp <line...>
$lines = Get-Content "scripts\qmp-steps.txt"
foreach ($line in $lines) {
  $line = $line.Trim()
  if ($line -eq "" -or $line.StartsWith("#")) { continue }
  $parts = $line -split '\s+', 3
  $pod = "loco-loco-emulator-$($parts[0])"
  $cmd = $parts[1]
  $arg = if ($parts.Count -gt 2) { $parts[2] } else { "" }
  switch ($cmd) {
    "key"   { & $Kube exec $pod -n loco -- python3 /usr/local/bin/qmp-control.py sendkey $arg 2>&1 | Out-Null; Start-Sleep -Milliseconds 350 }
    "sleep" { Start-Sleep -Seconds ([double]$arg) }
    "hmp"   { Write-Host "hmp[$pod]: $arg"; & $Kube exec $pod -n loco -- python3 /usr/local/bin/qmp-control.py hmp $arg 2>&1 }
    "dump"  {
      & $Kube exec $pod -n loco -- python3 /usr/local/bin/qmp-control.py screendump "/tmp/$($arg).ppm" 2>&1 | Out-Null
      & $Kube cp -n loco "${pod}:tmp/$($arg).ppm" "scripts/out/$($arg).ppm" 2>&1 | Out-Null
      Write-Host "dumped $arg"
    }
    default { Write-Host "unknown cmd: $line" }
  }
}
Write-Host "=== DONE ==="
