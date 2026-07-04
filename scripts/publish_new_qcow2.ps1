# Publish New Win98 SoftGPU QCOW2 Image
$ErrorActionPreference = 'Stop'
$RepoRoot = (Get-Location).Path
$ImagesDir = Join-Path $RepoRoot "images"
$QcowFile = Join-Path $ImagesDir "win98.qcow2"

if (-not (Test-Path $QcowFile)) {
    Write-Error "Cannot find $QcowFile. Please run run-qemu-interactive.ps1 to create/modify it first."
    exit 1
}

Write-Host "Creating a temporary build context..."
$TempContext = Join-Path $RepoRoot "containers/qemu-softgpu/tmp-build"
if (Test-Path $TempContext) { Remove-Item -Recurse -Force $TempContext }
New-Item -ItemType Directory -Path $TempContext | Out-Null

Copy-Item $QcowFile (Join-Path $TempContext "win98.qcow2.builtin")

$DockerFileContent = @"
FROM ghcr.io/mroie/lego-loco-cluster/win98-softgpu:latest
COPY win98.qcow2.builtin /opt/builtin-images/win98.qcow2.builtin
"@

Set-Content (Join-Path $TempContext "Dockerfile") $DockerFileContent

$ImageName = "ghcr.io/mroie/lego-loco-cluster/win98-softgpu:latest"

Write-Host "Building Docker image $ImageName..."
Push-Location $TempContext
docker build -t $ImageName .
Pop-Location

Write-Host "Pushing Docker image $ImageName..."
docker push $ImageName

Write-Host "Cleaning up temp build context..."
Remove-Item -Recurse -Force $TempContext

Write-Host "Done! The new softgpu snapshot is published."
