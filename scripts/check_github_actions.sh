#!/bin/bash
# Check GitHub Actions workflow status

set -euo pipefail

REPO="MRoie/lego-loco-cluster"
WORKFLOW_NAME="Build and Push QEMU Docker Image"

echo "🔍 Checking GitHub Actions status for $REPO..."
echo "   Workflow: $WORKFLOW_NAME"
echo ""

# Check if gh CLI is available
if ! command -v gh &> /dev/null; then
    echo "⚠️  GitHub CLI (gh) not found. Please install it to check workflow status."
    echo "   Alternative: Check manually at https://github.com/$REPO/actions"
    exit 1
fi

# Get recent workflow runs
echo "📋 Recent workflow runs:"
gh run list --repo "$REPO" --workflow "$WORKFLOW_NAME" --limit 5

echo ""
echo "🔗 View all runs: https://github.com/$REPO/actions"
echo "🐳 Check published images: https://github.com/$REPO/pkgs/container/qemu-loco"
