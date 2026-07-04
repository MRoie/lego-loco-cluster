$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
$BinDir = Join-Path $RepoRoot ".bin"
New-Item -ItemType Directory -Force -Path $BinDir | Out-Null

Write-Host "=== Downloading kind ===" -ForegroundColor Cyan
$kindPath = Join-Path $BinDir "kind.exe"
if (-not (Test-Path $kindPath)) {
    Invoke-WebRequest -Uri "https://kind.sigs.k8s.io/dl/v0.20.0/kind-windows-amd64" -OutFile $kindPath
} else {
    Write-Host "kind.exe already present"
}

Write-Host "=== Downloading kubectl ===" -ForegroundColor Cyan
$kubectlPath = Join-Path $BinDir "kubectl.exe"
if (-not (Test-Path $kubectlPath)) {
    Invoke-WebRequest -Uri "https://dl.k8s.io/release/v1.28.4/bin/windows/amd64/kubectl.exe" -OutFile $kubectlPath
} else {
    Write-Host "kubectl.exe already present"
}

Write-Host "=== Downloading helm ===" -ForegroundColor Cyan
$helmZip = Join-Path $BinDir "helm.zip"
$helmExtractedDir = Join-Path $BinDir "helm-extract"
$helmPath = Join-Path $BinDir "helm.exe"
if (-not (Test-Path $helmPath)) {
    Invoke-WebRequest -Uri "https://get.helm.sh/helm-v3.13.3-windows-amd64.zip" -OutFile $helmZip
    Expand-Archive -Path $helmZip -DestinationPath $helmExtractedDir -Force
    Copy-Item (Join-Path $helmExtractedDir "windows-amd64\helm.exe") $helmPath -Force
} else {
    Write-Host "helm.exe already present"
}

Write-Host "=== Verifying tools ===" -ForegroundColor Cyan
& $kindPath version
& $kubectlPath version --client
& $helmPath version

Write-Host "=== DONE ===" -ForegroundColor Green
