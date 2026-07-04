# win98-rebuild-autorun.ps1
# Non-interactive: builds+starts a fresh QEMU container that boots
# images\win98-rebuild.qcow2 (from containers\win98_loco_qemu.qcow2, staged
# by stage-rebuild-files.bat) with images\win98se.iso attached as the
# install/boot CD. Boot order=dc so the CD gets first chance (press a key to
# run Setup); if left alone it falls through to the hard disk.
# 1024MB RAM, vga=vmware + usb-tablet for accurate absolute-position VNC mouse.

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path $MyInvocation.MyCommand.Path
$RepoRoot  = Split-Path $ScriptDir
$ImagesDir = Join-Path $RepoRoot "images"

function Send-Monitor($cmd) {
    Write-Host "[monitor] $cmd" -ForegroundColor Gray
    $script = "(echo '$cmd'; sleep 3) | nc -q 3 127.0.0.1 4444"
    docker exec win98_rebuild bash -c $script
}

if (!(Test-Path "$ImagesDir\win98-rebuild.qcow2") -or !(Test-Path "$ImagesDir\win98se.iso")) {
    Write-Host "Missing images\win98-rebuild.qcow2 or images\win98se.iso - run stage-rebuild-files.bat first." -ForegroundColor Red
    exit 1
}

$running = docker ps -q -f name=win98_rebuild
if (![string]::IsNullOrWhiteSpace($running)) {
    Write-Host "Container win98_rebuild already running - skipping build/start." -ForegroundColor Yellow
} else {
    $existing = docker ps -aq -f name=win98_rebuild
    if (![string]::IsNullOrWhiteSpace($existing)) {
        Write-Host "Removing stopped win98_rebuild container..." -ForegroundColor Yellow
        docker rm -f win98_rebuild | Out-Null
    }

    Write-Host "Building local QEMU rebuild-runner image (dynamic build)..." -ForegroundColor Yellow
    $TempContext = Join-Path $RepoRoot "scripts/tmp-build-qemu-rebuild"
    if (Test-Path $TempContext) { Remove-Item -Recurse -Force $TempContext }
    New-Item -ItemType Directory -Path $TempContext | Out-Null
    Copy-Item "$RepoRoot/scripts/custom-run-rebuild.sh" "$TempContext/custom-run-rebuild.sh"

    $DockerFileContent = @"
FROM ghcr.io/mroie/lego-loco-cluster/win98-softgpu:latest
USER root
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y websockify novnc netcat-openbsd
COPY custom-run-rebuild.sh /custom-run-rebuild.sh
RUN chmod +x /custom-run-rebuild.sh
ENTRYPOINT ["/custom-run-rebuild.sh"]
"@
    Set-Content "$TempContext/Dockerfile" $DockerFileContent

    Push-Location $TempContext
    docker build -q -t win98-rebuild-local .
    Pop-Location
    Remove-Item -Recurse -Force $TempContext

    Write-Host "Starting QEMU rebuild container (1024MB RAM, win98se.iso as boot CD)..." -ForegroundColor Green
    docker run -d --name win98_rebuild --rm `
      --cap-add=NET_ADMIN --device /dev/net/tun `
      -p 5901:5900 -p 6081:6080 `
      -v "$ImagesDir\win98-rebuild.qcow2:/vm/win98-rebuild.qcow2" `
      -v "$ImagesDir\win98se.iso:/vm/win98se.iso:ro" `
      win98-rebuild-local
}

Write-Host "Waiting for noVNC (localhost:6081) to come up..." -ForegroundColor Yellow
$up = $false
for ($i = 0; $i -lt 90; $i++) {
    Start-Sleep -Seconds 2
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $client.Connect("127.0.0.1", 6081)
        if ($client.Connected) { $up = $true; $client.Close(); break }
    } catch {}
}

if (-not $up) {
    Write-Host "noVNC did not come up in time - check 'docker logs win98_rebuild'." -ForegroundColor Red
} else {
    Write-Host "noVNC is up. Browser: http://localhost:6081/vnc.html  VNC: localhost:5901" -ForegroundColor Cyan
}

Write-Host ""
Write-Host "=== READY ===" -ForegroundColor Cyan
Write-Host "Open http://localhost:6081/vnc.html to interact with the boot/install process." -ForegroundColor Cyan
Write-Host "Monitor is on tcp 4444 inside the container (docker exec win98_rebuild ...)." -ForegroundColor Cyan
