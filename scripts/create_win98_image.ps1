<#
  create_win98_image.ps1 -- Convert a PCem or VHD disk image into raw and QCOW2 formats
  Usage: .\create_win98_image.ps1 <diskPath> [outDir]
#>

param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$DiskPath,

    [Parameter(Position=1)]
    [string]$OutDir = (Get-Location)
)

$ErrorActionPreference = 'Stop'

$LogFile = $env:LOG_FILE
if (-not $LogFile) { $LogFile = 'create_win98_image.log' }
Start-Transcript -Path $LogFile -Append | Out-Null

try {
    if (-not (Get-Command qemu-img.exe -ErrorAction SilentlyContinue)) {
        Write-Error 'qemu-img.exe is required but was not found in PATH.'
        exit 1
    }

    if (-not (Test-Path $DiskPath)) {
        Write-Error "Source disk $DiskPath not found"
        exit 1
    }

    if (-not (Test-Path $OutDir)) {
        New-Item -ItemType Directory -Path $OutDir | Out-Null
    }

    $rawOut = Join-Path $OutDir 'win98.img'
    $qcowOut = Join-Path $OutDir 'win98.qcow2'

    $inputFmt = 'raw'
    if ($DiskPath.ToLower().EndsWith('.vhd')) {
        $inputFmt = 'vpc'
    }

    Write-Host "==> Converting $DiskPath to raw image $rawOut"
    & qemu-img.exe convert -f $inputFmt -O raw $DiskPath $rawOut

    Write-Host "==> Converting $DiskPath to QCOW2 image $qcowOut"
    & qemu-img.exe convert -f $inputFmt -O qcow2 $DiskPath $qcowOut

    Write-Host "Images saved in $OutDir"
}
finally {
    Stop-Transcript | Out-Null
}
