#!/usr/bin/env bash
# check_build_status.sh -- Check GitHub Actions workflow status
set -euo pipefail

echo "==> Checking GitHub Actions workflow status..."

# Try to get workflow status using GitHub CLI if available
if command -v gh >/dev/null 2>&1; then
    echo "Using GitHub CLI to check workflow status:"
    gh run list --limit 5
else
    echo "GitHub CLI not available. Check workflow status manually at:"
    echo "https://github.com/MRoie/lego-loco-cluster/actions"
fi

echo ""
echo "==> Testing if Docker image is available in registry..."
if docker pull ghcr.io/mroie/qemu-loco:latest >/dev/null 2>&1; then
    echo "✅ Docker image is available in registry!"
    docker images ghcr.io/mroie/qemu-loco:latest
else
    echo "❌ Docker image not yet available in registry"
    echo "   Build may still be in progress or failed"
fi
