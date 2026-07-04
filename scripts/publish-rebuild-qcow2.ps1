# Publish the rebuilt Win98 SoftGPU QCOW2 image (images\win98-rebuild.qcow2)
# to ghcr.io/mroie/lego-loco-cluster/win98-softgpu.
#
# This bakes the disk image into the SAME path the rest of the stack expects
# at runtime (/opt/builtin-images/win98.qcow2.builtin) - see
# containers/qemu-softgpu/entrypoint.sh (BUILTIN_DISK fallback),
# containers/qemu-softgpu/Dockerfile (COPY --from=win98-extractor), and
# helm/loco-chart/templates/emulator-statefulset.yaml (init container copy).
#
# Tags pushed: :latest and a dated :win98-rebuild-YYYYMMDD tag for rollback.

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path $MyInvocation.MyCommand.Path
$RepoRoot  = Split-Path $ScriptDir
$ImagesDir = Join-Path $RepoRoot "images"
$QcowFile  = Join-Path $ImagesDir "win98-rebuild.qcow2"

if (-not (Test-Path $QcowFile)) {
    Write-Error "Cannot find $QcowFile."
    exit 1
}

# Make sure the rebuild container isn't mid-write to this file before we bake it in.
$running = docker ps -q -f name=win98_rebuild
if (![string]::IsNullOrWhiteSpace($running)) {
    Write-Host "Stopping win98_rebuild container to flush/quiesce the disk image..." -ForegroundColor Yellow
    docker exec win98_rebuild bash -c "(echo 'commit all'; sleep 3) | nc -q 3 127.0.0.1 4444" | Out-Null
    docker stop win98_rebuild | Out-Null
    Start-Sleep -Seconds 2
}

Write-Host "Source image: $QcowFile ($([math]::Round((Get-Item $QcowFile).Length / 1MB, 1)) MB)" -ForegroundColor Cyan

Write-Host "Creating a temporary build context..." -ForegroundColor Yellow
$TempContext = Join-Path $RepoRoot "containers/qemu-softgpu/tmp-build-rebuild"
if (Test-Path $TempContext) { Remove-Item -Recurse -Force $TempContext }
New-Item -ItemType Directory -Path $TempContext | Out-Null

Copy-Item $QcowFile (Join-Path $TempContext "win98.qcow2.builtin")

$DockerFileContent = @"
FROM ghcr.io/mroie/lego-loco-cluster/win98-softgpu:latest
COPY win98.qcow2.builtin /opt/builtin-images/win98.qcow2.builtin
RUN qemu-img info /opt/builtin-images/win98.qcow2.builtin
"@

Set-Content (Join-Path $TempContext "Dockerfile") $DockerFileContent

$DateTag   = Get-Date -Format "yyyyMMdd"
$BaseName  = "ghcr.io/mroie/lego-loco-cluster/win98-softgpu"
$LatestTag = "${BaseName}:latest"
$DatedTag  = "${BaseName}:win98-rebuild-${DateTag}"

Write-Host "Building Docker image $LatestTag / $DatedTag ..." -ForegroundColor Yellow
Push-Location $TempContext
docker build -t $LatestTag -t $DatedTag .
Pop-Location

Write-Host "Pushing $LatestTag ..." -ForegroundColor Yellow
docker push $LatestTag

Write-Host "Pushing $DatedTag ..." -ForegroundColor Yellow
docker push $DatedTag

Write-Host "Cleaning up temp build context..." -ForegroundColor Yellow
Remove-Item -Recurse -Force $TempContext

Write-Host "Done! Published $LatestTag and $DatedTag." -ForegroundColor Green
