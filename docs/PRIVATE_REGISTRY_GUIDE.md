# Private Registry Authentication Guide

This guide explains how to configure and use private container registries (GitHub Container Registry and JFrog Artifactory) with the LEGO Loco cluster.

## Overview

The LEGO Loco cluster supports pulling container images and snapshots from private registries using Kubernetes image pull secrets. This enables secure deployment in production environments where images are stored in private repositories.

## Supported Registries

### 1. GitHub Container Registry (GHCR)
- Registry URL: `ghcr.io`
- Authentication: GitHub Personal Access Token
- Use case: GitHub-hosted projects, CI/CD integration

### 2. JFrog Artifactory
- Registry URL: `your-company.jfrog.io`
- Authentication: Username + API Key
- Use case: Enterprise container management

## Quick Setup

### 1. Set up Authentication Secrets

```bash
# Configure GHCR credentials
export GHCR_USERNAME=your-github-username
export GHCR_TOKEN=ghp_your-personal-access-token

# Optional: Configure JFrog credentials
export JFROG_URL=your-company.jfrog.io
export JFROG_USERNAME=your-jfrog-username
export JFROG_TOKEN=your-jfrog-api-key

# Run setup script
./scripts/setup_registry_secrets.sh
```

### 2. Deploy with Private Registry Support

```bash
# Deploy using private registry values
helm install loco helm/loco-chart/ -f helm/loco-chart/values-private-registry.yaml

# Or customize inline
helm install loco helm/loco-chart/ \
  --set imagePullSecrets[0]=ghcr-secret \
  --set emulator.imagePullPolicy=Always \
  --set emulator.usePrebuiltSnapshot=true
```

## Detailed Configuration

### GitHub Personal Access Token Setup

1. **Navigate to GitHub Settings**
   - Go to GitHub Settings > Developer settings > Personal access tokens
   - Click "Generate new token (classic)"

2. **Configure Token Permissions**
   - Select appropriate expiration
   - Check `packages:read` scope (required for pulling)
   - Check `packages:write` scope (required for pushing)

3. **Save Token Securely**
   - Copy the generated token immediately
   - Store it securely (you won't be able to see it again)

### JFrog Artifactory Setup

1. **Access JFrog Instance**
   - Log into your JFrog Artifactory instance
   - Navigate to User Profile

2. **Generate API Key**
   - Go to "Generate API Key" or "User Profile"
   - Create new API key with appropriate permissions

3. **Configure Docker Repository**
   - Ensure Docker repositories are configured
   - Note the full registry URL (e.g., `company.jfrog.io`)

## Helm Chart Configuration

### Image Pull Secrets

The Helm chart supports configuring image pull secrets at the global level:

```yaml
# values.yaml
imagePullSecrets:
  - ghcr-secret      # GitHub Container Registry
  - jfrog-secret     # JFrog Artifactory
  - custom-secret    # Any custom registry

# Registry-specific configuration
registryConfig:
  ghcr:
    enabled: true
    secretName: "ghcr-secret"
    server: "ghcr.io"
  
  jfrog:
    enabled: true
    secretName: "jfrog-secret"
    server: "your-company.jfrog.io"
```

### Container Configuration

Each container can be configured with different pull policies:

```yaml
emulator:
  image: qemu-loco
  tag: latest
  imagePullPolicy: Always  # Always pull from registry

backend:
  image: loco-backend
  imagePullPolicy: IfNotPresent  # Use local if available

frontend:
  image: loco-frontend
  imagePullPolicy: Never  # Never pull, use local only
```

## Testing and Validation

### Test Private Registry Access

```bash
# Run comprehensive test
./scripts/test_private_registry_snapshots.sh

# Manual testing
kubectl run test-private --image=ghcr.io/mroie/qemu-loco:latest --restart=Never
kubectl logs test-private
kubectl delete pod test-private
```

### Verify Image Pull Secrets

```bash
# Check if secrets exist
kubectl get secrets | grep -E "(ghcr|jfrog)"

# Check service account configuration
kubectl get serviceaccount default -o yaml

# Test secret authentication
kubectl create job test-auth --image=ghcr.io/mroie/qemu-loco:latest -- echo "Auth test"
kubectl logs job/test-auth
kubectl delete job test-auth
```

## Troubleshooting

### Common Issues

1. **ImagePullBackOff Error**
   ```bash
   # Check pod events
   kubectl describe pod <pod-name>
   
   # Verify secret exists
   kubectl get secret ghcr-secret -o yaml
   
   # Check service account
   kubectl get serviceaccount default -o yaml
   ```

2. **401 Unauthorized**
   - Verify token has correct permissions
   - Check token expiration
   - Ensure repository is accessible with provided credentials

3. **Secret Not Found**
   ```bash
   # Recreate secrets
   ./scripts/setup_registry_secrets.sh
   
   # Verify secret creation
   kubectl get secrets
   ```

### Debug Commands

```bash
# Test registry access from within cluster
kubectl run debug --rm -it --image=alpine -- sh
# Inside pod:
# apk add curl
# curl -H "Authorization: Bearer $TOKEN" https://ghcr.io/v2/

# Check image pull logs
kubectl get events --sort-by=.metadata.creationTimestamp | grep -i image

# Decode secret to verify content
kubectl get secret ghcr-secret -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d
```

## Security Best Practices

### Token Management
- Use tokens with minimal required permissions
- Set appropriate expiration dates
- Rotate tokens regularly
- Store tokens securely (use secrets management)

### Network Security
- Use private networks when possible
- Implement network policies to restrict registry access
- Monitor registry access logs

### Cluster Security
- Limit service account permissions
- Use namespace isolation
- Regular security audits of deployed images

## Production Deployment

### Recommended Configuration

```yaml
# production-values.yaml
imagePullSecrets:
  - ghcr-secret

emulator:
  imagePullPolicy: Always
  usePrebuiltSnapshot: true
  snapshotRegistry: "ghcr.io/company/qemu-snapshots"
  
backend:
  imagePullPolicy: Always
  
frontend:
  imagePullPolicy: Always

# Enable registry monitoring
registryConfig:
  ghcr:
    enabled: true
    secretName: "ghcr-secret"
    server: "ghcr.io"
```

### Deployment Commands

```bash
# Production deployment
export GHCR_USERNAME=production-user
export GHCR_TOKEN=prod-token-with-limited-scope

# Setup authentication
./scripts/setup_registry_secrets.sh

# Deploy
helm install loco-prod helm/loco-chart/ \
  -f production-values.yaml \
  --namespace production \
  --create-namespace

# Verify deployment
kubectl get pods -n production
kubectl logs -l app=loco-prod-loco-emulator -n production
```

## Integration with CI/CD

### GitHub Actions Integration

```yaml
# .github/workflows/deploy.yml
- name: Setup Registry Authentication
  run: |
    export GHCR_USERNAME=${{ github.actor }}
    export GHCR_TOKEN=${{ secrets.GITHUB_TOKEN }}
    ./scripts/setup_registry_secrets.sh

- name: Deploy with Helm
  run: |
    helm upgrade --install loco helm/loco-chart/ \
      -f helm/loco-chart/values-private-registry.yaml
```

### Environment-Specific Deployments

```bash
# Development
export NAMESPACE=development
./scripts/test_private_registry_snapshots.sh

# Staging
export NAMESPACE=staging
export RELEASE_NAME=loco-staging
./scripts/test_private_registry_snapshots.sh

# Production
export NAMESPACE=production
export RELEASE_NAME=loco-production
./scripts/test_private_registry_snapshots.sh
```

## Support and Maintenance

### Monitoring
- Set up alerts for failed image pulls
- Monitor registry usage and costs
- Track token expiration dates

### Updates
- Regular updates to base images
- Security patches for containers
- Token rotation schedule

### Backup
- Backup registry credentials securely
- Document recovery procedures
- Test disaster recovery processes
