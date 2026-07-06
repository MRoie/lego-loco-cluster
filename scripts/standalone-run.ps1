$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
Set-Location $RepoRoot

# copy the Win98 ISO to a no-space path for a clean bind mount
$TempOnG = "G:\dev\.dockertemp"
New-Item -ItemType Directory -Path $TempOnG -Force | Out-Null
$isoSrc = "containers\Windows 98 Second Edition.iso"
$isoDst = "$TempOnG\win98se.iso"
if (-not (Test-Path $isoDst)) {
  Write-Host "=== copying ISO to $isoDst (626MB) [$(Get-Date -Format HH:mm:ss)] ==="
  Copy-Item $isoSrc $isoDst -Force
}
Write-Host "ISO ready: $([math]::Round((Get-Item $isoDst).Length/1MB,0)) MB"

Write-Host "=== remove any prior standalone container ==="
docker rm -f loco-standalone 2>&1 | Out-Null

Write-Host "=== docker run standalone emulator [$(Get-Date -Format HH:mm:ss)] ==="
docker run -d --name loco-standalone `
  --privileged --cap-add NET_ADMIN --cap-add SYS_ADMIN `
  --device /dev/net/tun `
  -e INSTANCE_INDEX=0 `
  -e USE_PREBUILT_SNAPSHOT=false `
  -e ENABLE_GUEST_L2_MESH=false `
  -e ENABLE_GUEST_DHCP=true `
  -e SNAPSHOT_MODE=persistent `
  -e QEMU_EXTRA_ARGS="-drive file=/images/win98se.iso,format=raw,media=cdrom,readonly=on,if=ide,index=2" `
  -v "${isoDst}:/images/win98se.iso:ro" `
  -p 5901:5901 -p 8080:8080 `
  lego-loco-emulator:lan-test-flat 2>&1
Write-Host "run exit: $LASTEXITCODE"

Start-Sleep -Seconds 40
Write-Host "=== container status ==="
docker ps -a --format "{{.Names}} {{.Status}}" 2>&1 | Select-String "loco-standalone"
Write-Host "=== logs (tail) ==="
docker logs --tail 40 loco-standalone 2>&1
Write-Host "=== DONE ==="
