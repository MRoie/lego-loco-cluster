# ============================================================================
# push-golden-image.ps1 — build OCI carriers from the clean golden qcow2 and
# push them to GHCR.
# ============================================================================
# Produces two carriers from a single data payload:
#   1. win98-loco-golden:safe512-v1  (Android)  -> /opt/builtin-images/win98.qcow2.builtin
#   2. emulator-snapshot:<tag>        (cluster)  -> /<tag>.qcow2 at image root
#
# GHCR needs a CLASSIC PAT with the `write:packages` scope. The `gho_` OAuth
# token in Git Credential Manager (scopes gist/repo/workflow) CANNOT push —
# create a classic token: GitHub > Settings > Developer settings >
# Personal access tokens (classic) > Generate > check write:packages (+ repo).
#
# Provide it one of two ways:
#   $env:GHCR_TOKEN = 'ghp_xxx'      ; then run this script (it logs in), or
#   docker login ghcr.io -u MRoie    ; (paste the PAT) then run with -SkipLogin
#
# Usage:
#   pwsh scripts/push-golden-image.ps1                     # golden + cluster tags
#   pwsh scripts/push-golden-image.ps1 -MultiArch          # amd64+arm64 (buildx)
#   pwsh scripts/push-golden-image.ps1 -GoldenOnly         # just the Android tag
#   pwsh scripts/push-golden-image.ps1 -SkipLogin          # already docker-logged-in
# ============================================================================
param(
  [string]$Qcow2   = "containers/win98-loco-golden-safe512.qcow2",
  [string]$User    = "MRoie",
  [string]$GoldenTag = "ghcr.io/mroie/lego-loco-cluster/win98-loco-golden:safe512-v1",
  [string[]]$SnapshotTags = @(
    "ghcr.io/mroie/lego-loco-cluster/emulator-snapshot:hostgame",
    "ghcr.io/mroie/lego-loco-cluster/emulator-snapshot:joingame",
    "ghcr.io/mroie/lego-loco-cluster/emulator-snapshot:clean-safe512"
  ),
  [switch]$MultiArch,
  [switch]$GoldenOnly,
  [switch]$SkipLogin
)
$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
Set-Location $RepoRoot

if (-not (Test-Path $Qcow2)) { Write-Error "qcow2 not found: $Qcow2 (copy the golden image there first)"; exit 1 }
Write-Host "Payload: $Qcow2 ($((Get-Item $Qcow2).Length) bytes)"

# --- Login -----------------------------------------------------------------
if (-not $SkipLogin) {
  if (-not $env:GHCR_TOKEN) {
    Write-Error "Set `$env:GHCR_TOKEN to a classic PAT with write:packages, or pass -SkipLogin after 'docker login ghcr.io'."
    exit 1
  }
  $env:GHCR_TOKEN | docker login ghcr.io -u $User --password-stdin
  if ($LASTEXITCODE -ne 0) { Write-Error "docker login failed"; exit 1 }
}

# --- Build context (FROM scratch carriers) ---------------------------------
$Ctx = Join-Path $env:TEMP "loco-golden-ctx"
if (Test-Path $Ctx) { Remove-Item -Recurse -Force $Ctx }
New-Item -ItemType Directory -Force $Ctx | Out-Null
Copy-Item $Qcow2 (Join-Path $Ctx "payload.qcow2")

function Push-Carrier([string]$Tag, [string]$DestPath) {
  $df = Join-Path $Ctx "Dockerfile"
  "FROM scratch`nCOPY payload.qcow2 $DestPath" | Set-Content -Encoding ascii $df
  if ($MultiArch) {
    Write-Host "=== buildx push (amd64+arm64): $Tag ==="
    docker buildx build --platform linux/amd64,linux/arm64 -f $df -t $Tag --push $Ctx
  } else {
    Write-Host "=== build + push (amd64): $Tag ==="
    docker build -f $df -t $Tag $Ctx
    docker push $Tag
  }
  if ($LASTEXITCODE -ne 0) { Write-Error "push failed for $Tag"; exit 1 }
}

# Android golden: builtin path expected by the emulator/golden-image runtime.
Push-Carrier $GoldenTag "/opt/builtin-images/win98.qcow2.builtin"

# Cluster snapshot tags: qcow2 at root named <tag>.qcow2 (matches how the
# existing emulator-snapshot carriers were structured).
if (-not $GoldenOnly) {
  foreach ($t in $SnapshotTags) {
    $name = ($t -split ':')[-1]
    Push-Carrier $t "/$name.qcow2"
  }
}

Write-Host "=== DONE ==="
Write-Host "Pushed: $GoldenTag" + $(if (-not $GoldenOnly) { "`n        " + ($SnapshotTags -join "`n        ") })
