$ErrorActionPreference = 'Continue'
Write-Host "=== %LOCALAPPDATA%\Docker tree (top levels) ==="
$dockerLA = Join-Path $env:LOCALAPPDATA "Docker"
if (Test-Path $dockerLA) {
    Get-ChildItem $dockerLA -Recurse -Depth 2 -ErrorAction SilentlyContinue |
        Select-Object FullName, @{N='SizeMB';E={if($_.PSIsContainer){''}else{[math]::Round($_.Length/1MB,1)}}} |
        Format-Table -AutoSize | Out-String -Width 300
} else {
    Write-Host "NOT FOUND: $dockerLA"
}

Write-Host "=== vhdx files under %LOCALAPPDATA%\Docker ==="
Get-ChildItem $dockerLA -Recurse -Filter *.vhdx -ErrorAction SilentlyContinue |
    Select-Object FullName, @{N='SizeGB';E={[math]::Round($_.Length/1GB,2)}} | Format-Table -AutoSize | Out-String -Width 300

Write-Host "=== WSL distros (wsl -l -v) ==="
wsl -l -v 2>&1

Write-Host "=== Existing Defender exclusions (current state, read-only) ==="
Get-MpPreference | Select-Object -ExpandProperty ExclusionPath
Write-Host "--- exclusion processes ---"
Get-MpPreference | Select-Object -ExpandProperty ExclusionProcess

Write-Host "=== DONE ==="
