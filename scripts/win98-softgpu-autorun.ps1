# win98-softgpu-autorun.ps1
# Fully non-interactive version of run-qemu-interactive.ps1's "Start" flow.
# Dynamically builds the local win98-softgpu QEMU runner image, starts the
# container (1024MB RAM + softgpu.iso attached, per custom-run.sh), waits for
# noVNC to come up, then takes a baseline live snapshot before any driver
# work begins. No stdin/menu input required -> safe to launch by double-click.

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path $MyInvocation.MyCommand.Path
$RepoRoot  = Split-Path $ScriptDir
$ImagesDir = Join-Path $RepoRoot "images"

if (!(Test-Path $ImagesDir)) { New-Item -ItemType Directory -Path $ImagesDir | Out-Null }

function Send-Monitor($cmd) {
    Write-Host "[monitor] $cmd" -ForegroundColor Gray
    $script = "(echo '$cmd'; sleep 3) | nc -q 3 127.0.0.1 4444"
    docker exec win98_interactive_softgpu bash -c $script
}

$running = docker ps -q -f name=win98_interactive_softgpu
if (![string]::IsNullOrWhiteSpace($running)) {
    Write-Host "Container already running - skipping build/start." -ForegroundColor Yellow
} else {
    if (!(Test-Path "$ImagesDir\win98.qcow2")) {
        Write-Host "Extracting base win98.qcow2 from container image..." -ForegroundColor Yellow
        docker run --rm --entrypoint cp -v "$($ImagesDir):/out" ghcr.io/mroie/lego-loco-cluster/win98-softgpu:latest /opt/builtin-images/win98.qcow2.builtin /out/win98.qcow2
    }

    Write-Host "Building local QEMU runner image (dynamic build)..." -ForegroundColor Yellow
    $TempContext = Join-Path $RepoRoot "scripts/tmp-build-qemu-auto"
    if (Test-Path $TempContext) { Remove-Item -Recurse -Force $TempContext }
    New-Item -ItemType Directory -Path $TempContext | Out-Null
    Copy-Item "$RepoRoot/scripts/custom-run.sh" "$TempContext/custom-run.sh"

    $DockerFileContent = @"
FROM ghcr.io/mroie/lego-loco-cluster/win98-softgpu:latest
USER root
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y websockify novnc netcat-openbsd
COPY custom-run.sh /custom-run.sh
RUN chmod +x /custom-run.sh
ENTRYPOINT ["/custom-run.sh"]
"@
    Set-Content "$TempContext/Dockerfile" $DockerFileContent

    Push-Location $TempContext
    docker build -q -t win98-softgpu-local .
    Pop-Location
    Remove-Item -Recurse -Force $TempContext

    Write-Host "Starting QEMU container (1024MB RAM, softgpu.iso mounted)..." -ForegroundColor Green
    docker run -d --name win98_interactive_softgpu --rm `
      --cap-add=NET_ADMIN --device /dev/net/tun `
      -p 5900:5900 -p 6080:6080 `
      -v "$ImagesDir\win98.qcow2:/vm/win98.qcow2" `
      -v "$ImagesDir\softgpu.iso:/vm/softgpu.iso" `
      win98-softgpu-local
}

Write-Host "Waiting for noVNC (localhost:6080) to come up..." -ForegroundColor Yellow
$up = $false
for ($i = 0; $i -lt 90; $i++) {
    Start-Sleep -Seconds 2
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $client.Connect("127.0.0.1", 6080)
        if ($client.Connected) { $up = $true; $client.Close(); break }
    } catch {}
}

if (-not $up) {
    Write-Host "noVNC did not come up in time - check 'docker logs win98_interactive_softgpu'." -ForegroundColor Red
} else {
    Write-Host "noVNC is up. Browser: http://localhost:6080/vnc.html  VNC: localhost:5900" -ForegroundColor Cyan
    Write-Host "Giving the guest a few more seconds to reach a stable state before snapshotting..." -ForegroundColor Yellow
    Start-Sleep -Seconds 10
    Send-Monitor "savevm baseline-before-drivers"
    Write-Host "Baseline snapshot 'baseline-before-drivers' saved." -ForegroundColor Green
}

Write-Host ""
Write-Host "=== READY ===" -ForegroundColor Cyan
Write-Host "Open http://localhost:6080/vnc.html to interact with the Win98 desktop." -ForegroundColor Cyan
