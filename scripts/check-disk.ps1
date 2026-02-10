# Check disk space and Docker leftovers
Write-Host "=== Disk Space ==="
Get-PSDrive -PSProvider FileSystem | ForEach-Object {
    $freeGB = [math]::Round($_.Free / 1GB, 2)
    $usedGB = [math]::Round($_.Used / 1GB, 2)
    Write-Host "  Drive $($_.Name): Free=$freeGB GB, Used=$usedGB GB"
}

Write-Host "`n=== Docker VHDX files in AppData ==="
$dockerPath = Join-Path $env:LOCALAPPDATA "Docker"
if (Test-Path $dockerPath) {
    Get-ChildItem -Path $dockerPath -Filter "*.vhdx" -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
        $sizeGB = [math]::Round($_.Length / 1GB, 2)
        Write-Host "  $($_.FullName) - $sizeGB GB"
    }
} else {
    Write-Host "  No Docker AppData folder found"
}

Write-Host "`n=== WSL VHDX files ==="
$wslPath = Join-Path $env:LOCALAPPDATA "Packages"
Get-ChildItem -Path $wslPath -Filter "ext4.vhdx" -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
    $sizeGB = [math]::Round($_.Length / 1GB, 2)
    Write-Host "  $($_.FullName) - $sizeGB GB"
}

Write-Host "`n=== Temp files size ==="
$tempSize = (Get-ChildItem $env:TEMP -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
Write-Host "  Temp folder: $([math]::Round($tempSize / 1GB, 2)) GB"

Write-Host "`n=== Docker data directory ==="
$dockerWslPath = Join-Path $env:LOCALAPPDATA "Docker\wsl"
if (Test-Path $dockerWslPath) {
    $dockerWslSize = (Get-ChildItem $dockerWslPath -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
    Write-Host "  Docker WSL data: $([math]::Round($dockerWslSize / 1GB, 2)) GB"
}
