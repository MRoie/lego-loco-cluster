$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
Set-Location $RepoRoot
$env:GIT_PAGER = 'cat'
$env:GIT_TERMINAL_PROMPT = '0'   # fail instead of hanging if creds are needed

Write-Host "=== staging today's assets ==="
git add scripts/qmp-steps.ps1 scripts/qmp-steps.bat scripts/qmp-steps.txt 2>&1
git add scripts/qmp-winipcfg.ps1 scripts/qmp-winipcfg.bat 2>&1
git add scripts/diag-guest-net.ps1 scripts/diag-guest-net.bat 2>&1
git add scripts/check-net2.ps1 scripts/check-net2.bat 2>&1
git add scripts/check-dplay.ps1 scripts/check-dplay.bat 2>&1
git add scripts/check-storage.ps1 scripts/check-storage.bat 2>&1
git add scripts/win98cd-patch.yaml scripts/apply-win98cd.ps1 scripts/apply-win98cd.bat scripts/apply-win98cd2.ps1 scripts/apply-win98cd2.bat 2>&1
git add scripts/reset-vms.ps1 scripts/reset-vms.bat 2>&1
git add scripts/fix-audio.ps1 scripts/fix-audio.bat 2>&1
git add scripts/pf-frontend-loop.ps1 scripts/pf-frontend-loop.bat scripts/probe-iso.ps1 scripts/probe-iso.bat 2>&1
git add scripts/ghcr-inventory.ps1 scripts/ghcr-inventory.bat 2>&1
git add scripts/out/w0x.png scripts/out/w1x.png 2>&1

Write-Host "=== staged summary ==="
git status --porcelain 2>&1

Write-Host "=== commit ==="
git commit -m "LAN multiplayer bring-up: guest NIC install + Win98 CD patch, QMP step runner, net/dplay diagnostics, GHCR inventory, multiplayer game-world proof captures" 2>&1

Write-Host "=== current branch + ahead count ==="
$branch = git rev-parse --abbrev-ref HEAD 2>&1
Write-Host "branch: $branch"
git log origin/$branch..HEAD --oneline 2>&1

Write-Host "=== push ==="
git push origin HEAD 2>&1
Write-Host "push exit code: $LASTEXITCODE"
Write-Host "=== DONE ==="
