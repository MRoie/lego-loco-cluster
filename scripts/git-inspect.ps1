$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
Set-Location $RepoRoot

Write-Host "=== recent commits ==="
git log --oneline -12 2>&1
Write-Host "=== are today's key files tracked? ==="
foreach ($f in @("scripts/qmp-steps.ps1","scripts/win98cd-patch.yaml","scripts/apply-win98cd2.ps1","scripts/reset-vms.ps1","scripts/diag-guest-net.ps1","scripts/check-net2.ps1")) {
  $tracked = git ls-files --error-unmatch $f 2>$null
  if ($LASTEXITCODE -eq 0) { Write-Host "TRACKED   $f" } else { Write-Host "UNTRACKED $f" }
}
Write-Host "=== last commit date + author ==="
git log -1 --format="%h %ci %an %s" 2>&1
Write-Host "=== ahead/behind origin ==="
git rev-list --left-right --count origin/feat/interactive-softgpu-config...HEAD 2>&1
Write-Host "=== DONE ==="
