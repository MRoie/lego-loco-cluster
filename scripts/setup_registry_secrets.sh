#!/usr/bin/env bash
# setup_registry_secrets.sh -- Setup image pull secrets for private registries

set -euo pipefail

# Configuration
NAMESPACE=${NAMESPACE:-default}
GHCR_USERNAME=${GHCR_USERNAME:-""}
GHCR_TOKEN=${GHCR_TOKEN:-""}
JFROG_URL=${JFROG_URL:-""}
JFROG_USERNAME=${JFROG_USERNAME:-""}
JFROG_TOKEN=${JFROG_TOKEN:-""}

# Function to auto-detect GitHub CLI credentials
auto_detect_github_credentials() {
    # Check if GitHub CLI is installed and logged in
    if command -v gh >/dev/null 2>&1; then
        echo "🔍 Checking for GitHub CLI session..."
        
        # Check if logged in
        if gh auth status >/dev/null 2>&1; then
            # Get username
            local gh_username
            gh_username=$(gh api user --jq '.login' 2>/dev/null || echo "")
            
            # Get token
            local gh_token
            gh_token=$(gh auth token 2>/dev/null || echo "")
            
            if [[ -n "$gh_username" && -n "$gh_token" ]]; then
                echo "   ✅ Found GitHub CLI session for user: $gh_username"
                
                # Only use auto-detected credentials if not explicitly set
                if [[ -z "$GHCR_USERNAME" ]]; then
                    GHCR_USERNAME="$gh_username"
                    echo "   📝 Auto-detected GHCR_USERNAME: $GHCR_USERNAME"
                fi
                
                if [[ -z "$GHCR_TOKEN" ]]; then
                    GHCR_TOKEN="$gh_token"
                    echo "   📝 Auto-detected GHCR_TOKEN from GitHub CLI"
                fi
                
                return 0
            fi
        fi
    fi
    
    echo "   ⚠️  No GitHub CLI session found or not logged in"
    return 1
}

echo "🔐 Setting up registry authentication secrets"
echo "=============================================="
echo "Namespace: $NAMESPACE"
echo ""

# Function to create Docker registry secret
create_docker_secret() {
    local secret_name=$1
    local registry_url=$2
    local username=$3
    local password=$4
    local email=${5:-"noreply@example.com"}
    
    echo "📝 Creating secret: $secret_name for registry: $registry_url"
    
    # Check if secret already exists
    if kubectl get secret "$secret_name" -n "$NAMESPACE" >/dev/null 2>&1; then
        echo "   Secret already exists, deleting..."
        kubectl delete secret "$secret_name" -n "$NAMESPACE"
    fi
    
    # Create the secret
    kubectl create secret docker-registry "$secret_name" \
        --docker-server="$registry_url" \
        --docker-username="$username" \
        --docker-password="$password" \
        --docker-email="$email" \
        --namespace="$NAMESPACE"
    
    echo "   ✅ Secret created successfully"
}

# Function to patch service account to use image pull secrets
patch_service_account() {
    local service_account=${1:-default}
    local secret_names=("$@")
    
    echo "🔧 Patching service account: $service_account"
    
    # Build the patch JSON for multiple secrets
    local patch_json='{"imagePullSecrets":['
    for secret in "${secret_names[@]:1}"; do  # Skip first element (service account name)
        if [[ "$patch_json" != '{"imagePullSecrets":[' ]]; then
            patch_json+=","
        fi
        patch_json+="{\"name\":\"$secret\"}"
    done
    patch_json+=']}'
    
    echo "   Applying patch: $patch_json"
    kubectl patch serviceaccount "$service_account" -n "$NAMESPACE" -p "$patch_json"
    echo "   ✅ Service account patched successfully"
}

# Setup GitHub Container Registry (GHCR) authentication
setup_ghcr_auth() {
    if [[ -n "$GHCR_USERNAME" && -n "$GHCR_TOKEN" ]]; then
        echo "🐙 Setting up GitHub Container Registry authentication..."
        create_docker_secret "ghcr-secret" "ghcr.io" "$GHCR_USERNAME" "$GHCR_TOKEN"
        echo ""
    else
        echo "⚠️  GHCR credentials not provided. Set GHCR_USERNAME and GHCR_TOKEN to enable."
        echo "   Example: export GHCR_USERNAME=your-github-username"
        echo "   Example: export GHCR_TOKEN=ghp_your-personal-access-token"
        echo ""
    fi
}

# Setup JFrog Artifactory authentication
setup_jfrog_auth() {
    if [[ -n "$JFROG_URL" && -n "$JFROG_USERNAME" && -n "$JFROG_TOKEN" ]]; then
        echo "🐸 Setting up JFrog Artifactory authentication..."
        create_docker_secret "jfrog-secret" "$JFROG_URL" "$JFROG_USERNAME" "$JFROG_TOKEN"
        echo ""
    else
        echo "⚠️  JFrog credentials not provided. Set JFROG_URL, JFROG_USERNAME, and JFROG_TOKEN to enable."
        echo "   Example: export JFROG_URL=your-company.jfrog.io"
        echo "   Example: export JFROG_USERNAME=your-jfrog-username"
        echo "   Example: export JFROG_TOKEN=your-jfrog-api-key"
        echo ""
    fi
}

# Main execution
main() {
    echo "🚀 Starting registry authentication setup..."
    echo ""
    
    # Auto-detect GitHub credentials from CLI session
    auto_detect_github_credentials
    echo ""
    
    # Create namespace if it doesn't exist
    if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
        echo "📁 Creating namespace: $NAMESPACE"
        kubectl create namespace "$NAMESPACE"
    fi
    
    # Setup authentication for different registries
    setup_ghcr_auth
    setup_jfrog_auth
    
    # Collect all created secrets
    local secrets=()
    if kubectl get secret ghcr-secret -n "$NAMESPACE" >/dev/null 2>&1; then
        secrets+=("ghcr-secret")
    fi
    if kubectl get secret jfrog-secret -n "$NAMESPACE" >/dev/null 2>&1; then
        secrets+=("jfrog-secret")
    fi
    
    # Patch service account if we have secrets
    if [[ ${#secrets[@]} -gt 0 ]]; then
        echo "🔗 Configuring service account to use image pull secrets..."
        patch_service_account "default" "${secrets[@]}"
        echo ""
    fi
    
    # Display status
    echo "📊 Registry Authentication Status:"
    echo "=================================="
    if kubectl get secret ghcr-secret -n "$NAMESPACE" >/dev/null 2>&1; then
        echo "  ✅ GitHub Container Registry (GHCR): Configured"
    else
        echo "  ❌ GitHub Container Registry (GHCR): Not configured"
    fi
    
    if kubectl get secret jfrog-secret -n "$NAMESPACE" >/dev/null 2>&1; then
        echo "  ✅ JFrog Artifactory: Configured"
    else
        echo "  ❌ JFrog Artifactory: Not configured"
    fi
    
    echo ""
    echo "🎯 Registry authentication setup complete!"
    echo ""
    echo "💡 Usage Tips:"
    echo "   - Pods will automatically use these secrets for image pulls"
    echo "   - To manually specify: add 'imagePullSecrets:' to pod specs"
    echo "   - Test with: kubectl run test --image=ghcr.io/your-org/image:tag"
    echo ""
}

# Help function
show_help() {
    cat << EOF
Setup Registry Authentication Secrets

This script sets up Kubernetes secrets for authenticating with private container registries.

USAGE:
    ./setup_registry_secrets.sh [options]

ENVIRONMENT VARIABLES:
    NAMESPACE         Target Kubernetes namespace (default: default)
    
    GitHub Container Registry (GHCR):
    GHCR_USERNAME     GitHub username (auto-detected from 'gh' CLI if available)
    GHCR_TOKEN        GitHub Personal Access Token (auto-detected from 'gh' CLI if available)
    
    JFrog Artifactory:
    JFROG_URL         JFrog instance URL (e.g., your-company.jfrog.io)
    JFROG_USERNAME    JFrog username
    JFROG_TOKEN       JFrog API key or password

AUTO-DETECTION:
    The script automatically detects GitHub credentials if you're logged in with 'gh' CLI.
    Run 'gh auth login' to authenticate with GitHub first.
    Manual environment variables override auto-detected values.

EXAMPLES:
    # Auto-detect GitHub credentials (if logged in with 'gh' CLI)
    ./setup_registry_secrets.sh
    
    # Manual GHCR authentication
    export GHCR_USERNAME=myuser
    export GHCR_TOKEN=ghp_xxxxxxxxxxxx
    ./setup_registry_secrets.sh
    
    # Setup both GHCR and JFrog
    export GHCR_USERNAME=myuser
    export GHCR_TOKEN=ghp_xxxxxxxxxxxx
    export JFROG_URL=mycompany.jfrog.io
    export JFROG_USERNAME=myuser
    export JFROG_TOKEN=myapikey
    ./setup_registry_secrets.sh
    
    # Target specific namespace
    export NAMESPACE=production
    ./setup_registry_secrets.sh

GITHUB TOKEN SETUP:
    1. Go to GitHub Settings > Developer settings > Personal access tokens
    2. Generate new token with 'packages:read' scope (and 'packages:write' if pushing)
    3. Use the token as GHCR_TOKEN

JFROG TOKEN SETUP:
    1. Log into your JFrog instance
    2. Go to User Profile > Generate API Key
    3. Use the API key as JFROG_TOKEN
EOF
}

# Parse command line arguments
case "${1:-}" in
    -h|--help)
        show_help
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac
