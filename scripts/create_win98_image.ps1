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
    $qemuImg = Get-Command qemu-img -ErrorAction SilentlyContinue
    if (-not $qemuImg) {
        $qemuImg = Get-Command qemu-img.exe -ErrorAction SilentlyContinue
    }
    if (-not $qemuImg) {
        Write-Error 'qemu-img is required but was not found in PATH.'
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
    & $qemuImg convert -p -f $inputFmt -O raw $DiskPath $rawOut

    # Verify MBR signature
    $fs = [System.IO.File]::Open($rawOut, 'Open', 'Read')
    $fs.Seek(510, 'Begin') | Out-Null
    $sig = New-Object byte[] 2
    $fs.Read($sig, 0, 2) | Out-Null
    $fs.Close()
    if ($sig[0] -ne 0x55 -or $sig[1] -ne 0xAA) {
        Write-Warning 'MBR signature not found; image may not be bootable.'
    }

    Write-Host "==> Converting $DiskPath to QCOW2 image $qcowOut"
    & $qemuImg convert -p -f $inputFmt -O qcow2 -o compat=0.10 $DiskPath $qcowOut

    Write-Host "Images saved in $OutDir"
}
finally {
    Stop-Transcript | Out-Null
}
