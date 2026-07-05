$ErrorActionPreference = 'Continue'
Write-Host "=== gh CLI available? ==="
where.exe gh 2>&1
gh --version 2>&1
Write-Host "=== gh auth status ==="
gh auth status 2>&1
Write-Host "=== docker login identity for ghcr.io ==="
Get-Content "$env:USERPROFILE\.docker\config.json" -ErrorAction SilentlyContinue
Write-Host "=== DONE ==="
