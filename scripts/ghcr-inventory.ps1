$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
$BinDir = Join-Path $RepoRoot ".bin"
$env:PATH = "$BinDir;$env:PATH"
$env:KUBECONFIG = Join-Path $RepoRoot ".kube-config"
Set-Location $RepoRoot
$Kube = "$BinDir\kubectl.exe"

Write-Host "=== git remote (owner detection) ==="
git remote -v 2>&1 | Select-Object -First 2

Write-Host "=== images used by running pods ==="
& $Kube get pods -n loco -o jsonpath="{range .items[*]}{.metadata.name}{'\t'}{.spec.containers[*].image}{'\n'}{end}" 2>&1

Write-Host "=== images inside kind node (containerd) ==="
docker exec loco-control-plane crictl images 2>&1 | Select-String -Pattern "loco|emulator|backend|frontend" | Select-Object -First 15

Write-Host "=== host docker images (loco-related) ==="
docker images --format "{{.Repository}}:{{.Tag}}  {{.Size}}  {{.ID}}" 2>&1 | Select-String -Pattern "loco|win98|ghcr" | Select-Object -First 15

Write-Host "=== docker auth for ghcr.io ==="
$cfg = Join-Path $env:USERPROFILE ".docker\config.json"
if (Test-Path $cfg) {
  $j = Get-Content $cfg -Raw | ConvertFrom-Json
  if ($j.auths) { $j.auths.PSObject.Properties.Name | ForEach-Object { Write-Host "auth entry: $_" } }
  if ($j.credsStore) { Write-Host "credsStore: $($j.credsStore)" }
} else { Write-Host "no docker config.json" }

Write-Host "=== gh CLI auth ==="
gh auth status 2>&1 | Select-Object -First 6

Write-Host "=== test ghcr push access (dry: docker manifest inspect own image) ==="
docker manifest inspect ghcr.io/mroie/lego-loco-cluster/win98-softgpu:latest 2>&1 | Select-Object -First 3

Write-Host "=== git status (today's assets) ==="
git status --porcelain 2>&1 | Select-Object -First 60
Write-Host "=== DONE ==="
