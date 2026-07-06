$ErrorActionPreference = 'Stop'
$RepoRoot = (Get-Location).Path
$ImagesDir = Join-Path $RepoRoot "images"
$TempContext = Join-Path $RepoRoot "containers/qemu-softgpu/tmp-build-snapshots"

if (Test-Path $TempContext) { Remove-Item -Recurse -Force $TempContext }
New-Item -ItemType Directory -Path $TempContext | Out-Null

$Backups = @(Get-ChildItem -Path $ImagesDir -Filter "*.qcow2.bak")
if ($Backups.Count -eq 0) { 
    Write-Host "No snapshots found in $ImagesDir." -ForegroundColor Yellow
    exit 0 
}

foreach ($backup in $Backups) {
    $tagName = $backup.Name.Replace("win98-", "").Replace(".qcow2.bak", "")
    $ImageName = "ghcr.io/mroie/lego-loco-cluster/win98-softgpu:snapshot-$tagName"
    Write-Host ""
    Write-Host "Processing snapshot: $($backup.Name) -> $ImageName" -ForegroundColor Cyan
    
    # Copy the snapshot into the build context
    Copy-Item $backup.FullName (Join-Path $TempContext "win98.qcow2.builtin") -Force
    
    # Create the Dockerfile
    $DockerFileContent = 'FROM ghcr.io/mroie/lego-loco-cluster/win98-softgpu:latest' + "`n" + 'COPY win98.qcow2.builtin /opt/builtin-images/win98.qcow2.builtin'
    Set-Content (Join-Path $TempContext "Dockerfile") $DockerFileContent
    
    Push-Location $TempContext
    Write-Host "Building Docker image $ImageName..." -ForegroundColor Yellow
    docker build -t $ImageName .
    
    Write-Host "Pushing Docker image $ImageName..." -ForegroundColor Green
    docker push $ImageName
    Pop-Location
    
    Write-Host "Published: $ImageName" -ForegroundColor Green
}

Remove-Item -Recurse -Force $TempContext
Write-Host ""
Write-Host "All snapshots successfully uploaded!" -ForegroundColor Cyan