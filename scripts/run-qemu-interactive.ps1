$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path $ScriptDir
$ImagesDir = Join-Path $RepoRoot "images"

if (!(Test-Path $ImagesDir)) { New-Item -ItemType Directory -Path $ImagesDir | Out-Null }

function Get-QemuStatus {
    $status = docker ps -q -f name=win98_interactive_softgpu
    return (![string]::IsNullOrWhiteSpace($status))
}

function Show-Menu {
    $running = Get-QemuStatus
    Clear-Host
    Write-Host "=====================================================" -ForegroundColor Cyan
    Write-Host " Win98 SoftGPU Interactive & Snapshot Manager" -ForegroundColor White
    Write-Host "=====================================================" -ForegroundColor Cyan
    if ($running) {
        Write-Host "  STATUS: RUNNING" -ForegroundColor Green
        Write-Host "  -> VNC Client: localhost:5900" -ForegroundColor Cyan
        Write-Host "  -> Browser: http://localhost:6080/vnc.html" -ForegroundColor Cyan
        Write-Host "-----------------------------------------------------" -ForegroundColor Cyan
        Write-Host "1) Stop Windows 98"
        Write-Host "2) Create LIVE Snapshot (savevm) - for fast booting"
        Write-Host "3) Load LIVE Snapshot (loadvm)"
        Write-Host "4) List LIVE Snapshots inside VM"
        Write-Host "5) View Logs (Ctrl+C to exit logs)"
    } else {
        Write-Host "  STATUS: STOPPED" -ForegroundColor Yellow
        Write-Host "-----------------------------------------------------" -ForegroundColor Cyan
        Write-Host "1) Start Windows 98"
        Write-Host "2) Create Offline Checkpoint (Backup .qcow2)"
        Write-Host "3) Restore Offline Checkpoint"
        Write-Host "4) Reset to Fresh Base Image (Lose all progress)"
    }
    Write-Host "9) Exit Menu"
    Write-Host "=====================================================" -ForegroundColor Cyan
    return $running
}

function Start-Qemu {
    if (!(Test-Path "$ImagesDir\win98.qcow2")) {
        Write-Host "Extracting base win98.qcow2 from container image..." -ForegroundColor Yellow
        docker run --rm --entrypoint cp -v "$($ImagesDir):/out" ghcr.io/mroie/lego-loco-cluster/win98-softgpu:latest /opt/builtin-images/win98.qcow2.builtin /out/win98.qcow2
    }

    Write-Host "Building local QEMU runner..." -ForegroundColor Yellow
    $TempContext = Join-Path $RepoRoot "scripts/tmp-build-qemu"
    if (Test-Path $TempContext) { Remove-Item -Recurse -Force $TempContext }
    New-Item -ItemType Directory -Path $TempContext | Out-Null
    Copy-Item "$RepoRoot/scripts/custom-run.sh" "$TempContext/custom-run.sh"

    $DockerFileContent = "
FROM ghcr.io/mroie/lego-loco-cluster/win98-softgpu:latest
USER root
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y websockify novnc netcat-openbsd
COPY custom-run.sh /custom-run.sh
RUN chmod +x /custom-run.sh
ENTRYPOINT ["/custom-run.sh"]
"
    Set-Content "$TempContext/Dockerfile" $DockerFileContent

    Push-Location $TempContext
    docker build -q -t win98-softgpu-local . | Out-Null
    Pop-Location
    Remove-Item -Recurse -Force $TempContext

    Write-Host "Starting QEMU Container..." -ForegroundColor Green
    docker run -d --name win98_interactive_softgpu --rm 
      --cap-add=NET_ADMIN --device /dev/net/tun 
      -p 5900:5900 -p 6080:6080 
      -v "$ImagesDir\win98.qcow2:/vm/win98.qcow2" 
      -v "$ImagesDir\softgpu.iso:/vm/softgpu.iso" 
      win98-softgpu-local | Out-Null
      
    Start-Sleep -Seconds 2
}

function Stop-Qemu {
    Write-Host "Stopping QEMU..." -ForegroundColor Yellow
    docker stop win98_interactive_softgpu | Out-Null
}

function Execute-QemuMonitorCommand {
    param($cmd)
    Write-Host ""
    Write-Host "Executing online command: $cmd" -ForegroundColor Gray
    $script = "(echo \"$cmd\"; sleep 3) | nc -q 3 127.0.0.1 4444"
    Start-Process -NoNewWindow -Wait docker -ArgumentList "exec", "win98_interactive_softgpu", "bash", "-c", $script
}

function View-LiveSnapshots {
    Write-Host "
Live Snapshots inside QEMU:" -ForegroundColor Cyan
    $script = "(echo \"info snapshots\"; sleep 1) | nc -q 1 127.0.0.1 4444"
    docker exec win98_interactive_softgpu bash -c $script
    Read-Host "Press Enter to return..."
}

function Save-LiveState {
    Write-Host ""
    $name = Read-Host "Enter live state name (e.g., 'desktop-loaded')"
    if ([string]::IsNullOrWhiteSpace($name)) { return }
    Write-Host "Saving live state (this takes several seconds)..." -ForegroundColor Yellow
    Execute-QemuMonitorCommand "savevm $name"
    Write-Host "Done." -ForegroundColor Green
    Read-Host "Press Enter to return..."
}

function Load-LiveState {
    Write-Host ""
    $name = Read-Host "Enter live state name to load"
    if ([string]::IsNullOrWhiteSpace($name)) { return }
    Write-Host "Loading live state..." -ForegroundColor Yellow
    Execute-QemuMonitorCommand "loadvm $name"
    Write-Host "Done." -ForegroundColor Green
    Read-Host "Press Enter to return..."
}

function Create-Checkpoint {
    Write-Host ""
    $name = Read-Host "Enter checkpoint name (e.g. 'pre-drivers', 'after-first-reboot')"
    if ([string]::IsNullOrWhiteSpace($name)) { return }
    
    $source = Join-Path $ImagesDir "win98.qcow2"
    if (!(Test-Path $source)) {
        Write-Host "Error: No win98.qcow2 found to backup!" -ForegroundColor Red
    } else {
        $dest = Join-Path $ImagesDir "win98-$name.qcow2.bak"
        Copy-Item $source $dest -Force
        Write-Host "Success! Checkpoint saved as $(Split-Path $dest -Leaf)" -ForegroundColor Green
    }
    Read-Host "Press Enter to return..."
}

function Restore-Checkpoint {
    Write-Host ""
    $backups = @(Get-ChildItem -Path $ImagesDir -Filter "*.qcow2.bak")
    if ($backups.Count -eq 0) {
        Write-Host "No checkpoints found in $ImagesDir" -ForegroundColor Red
        Read-Host "Press Enter to return..."
        return
    }
    
    Write-Host "Available Offline Checkpoints:" -ForegroundColor Cyan
    for ($i=0; $i -lt $backups.Count; $i++) {
        $sizeMB = [math]::Round($backups[$i].Length / 1MB, 2)
        Write-Host "$($i+1)) $($backups[$i].Name) ($sizeMB MB)"
    }
    
    $choice = Read-Host "Select checkpoint to restore (1-$($backups.Count), or 0 to cancel)"
    $choiceNum = $choice -as [int]
    if ($choiceNum -gt 0 -and $choiceNum -le $backups.Count) {
        $selected = $backups[$choiceNum-1]
        $confirm = Read-Host "Overwrite current win98.qcow2 with $($selected.Name)? (y/n)"
        if ($confirm -eq 'y') {
            $dest = Join-Path $ImagesDir "win98.qcow2"
            Copy-Item $selected.FullName $dest -Force
            Write-Host "Success! Restored $($selected.Name)" -ForegroundColor Green
        }
    }
    Read-Host "Press Enter to return..."
}

function Reset-Base {
    Write-Host ""
    Write-Host "WARNING: This will overwrite current progress." -ForegroundColor Red
    $confirm = Read-Host "Are you sure? (y/n)"
    if ($confirm -eq 'y') {
        Write-Host "Extracting base win98.qcow2 from container image..." -ForegroundColor Yellow
        docker run --rm --entrypoint cp -v "$($ImagesDir):/out" ghcr.io/mroie/lego-loco-cluster/win98-softgpu:latest /opt/builtin-images/win98.qcow2.builtin /out/win98.qcow2
        Write-Host "Reset complete." -ForegroundColor Green
    }
    Read-Host "Press Enter to return..."
}

# Main Loop
while ($true) {
    $isRunning = Show-Menu
    $opt = Read-Host "Select option"
    
    if ($opt -eq '9') { exit }
    
    if ($isRunning) {
        switch ($opt) {
            '1' { Stop-Qemu }
            '2' { Save-LiveState }
            '3' { Load-LiveState }
            '4' { View-LiveSnapshots }
            '5' { 
                Write-Host "Showing logs. Press Ctrl+C to exit logs (system continues to run)." -ForegroundColor Cyan
                try { docker logs -f win98_interactive_softgpu } catch {} 
            }
        }
    } else {
        switch ($opt) {
            '1' { Start-Qemu }
            '2' { Create-Checkpoint }
            '3' { Restore-Checkpoint }
            '4' { Reset-Base }
        }
    }
}
