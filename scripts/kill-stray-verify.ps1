$ErrorActionPreference = 'Continue'
Write-Host "=== docker ps (all) ===" -ForegroundColor Cyan
docker ps -a

Write-Host "=== killing any lego-loco-emulator:lan-test containers not named lantest-export ===" -ForegroundColor Cyan
$ids = docker ps -q --filter "ancestor=lego-loco-emulator:lan-test"
foreach ($id in $ids) {
  Write-Host "Killing $id"
  docker kill $id 2>&1
  docker rm -f $id 2>&1
}

Write-Host "=== docker ps after cleanup ===" -ForegroundColor Cyan
docker ps -a

Write-Host "=== DONE ===" -ForegroundColor Green
