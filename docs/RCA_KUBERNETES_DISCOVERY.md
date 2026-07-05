# Root Cause Analysis: Kubernetes Discovery API Parameter Error

**Date:** 2025-08-14  
**Status:** ACTIVE - Production blocking issue  
**Priority:** CRITICAL  
**Issue ID:** K8S-DISCOVERY-001  

## Executive Summary

Production deployment is blocked by persistent Kubernetes API parameter error in service discovery. Despite multiple clean rebuilds and source code modifications, the error "Required parameter namespace was null or undefined when calling CoreV1Api.listNamespacedPod" persists at line 70, while source code shows different API calls at line 73.

## Problem Statement

### Primary Issue
- **Error:** `Required parameter namespace was null or undefined when calling CoreV1Api.listNamespacedPod`
- **Location:** Reported at line 70 in kubernetesDiscovery.js
- **Impact:** Production Kubernetes discovery completely non-functional
- **Workaround:** System runs with `ALLOW_EMPTY_DISCOVERY=true` (fallback mode)

### Secondary Issues
1. **Build/Deployment Inconsistency:** Source code changes not reflected in running containers despite clean rebuilds
2. **Line Number Mismatch:** Error reports line 70, but `listNamespacedPod` appears at line 120+ in source
3. **Cache Persistence:** Docker/Minikube caches persist despite aggressive cleanup

## Technical Context

### Environment
- **Platform:** Minikube Kubernetes cluster
- **Backend:** Node.js with @kubernetes/client-node
- **Deployment:** Helm chart with loco-backend:latest image
- **Namespace:** 'loco' (detected correctly)
- **RBAC:** Service account with proper permissions configured

### Code Archaeology
```javascript
// Current source at line 73 (working)
const nsResponse = await this.k8sApi.listNamespace();

// Error reports this at line 70 (failing)
await this.k8sApi.listNamespacedPod(namespace, labelSelector);
```

### API Client Evolution
1. **Initial:** Positional parameters `listNamespacedPod(namespace, labelSelector)`
2. **Current:** Object parameters `listNamespacedPod({ namespace, labelSelector })`
3. **Test:** Simple connectivity test with `listNamespace()`

## Root Cause Hypothesis

### Primary Hypothesis: Stale Container Image
- **Evidence:** Source shows line 73 with `listNamespace()`, error reports line 70 with `listNamespacedPod()`
- **Mechanism:** Docker layer caching or Minikube image persistence
- **Validation:** Multiple `--no-cache` rebuilds and minikube image cleanup attempted

### Secondary Hypothesis: API Client Version Mismatch
- **Evidence:** Parameter syntax inconsistency between documentation and actual behavior
- **Mechanism:** @kubernetes/client-node version incompatibility
- **Validation:** Need to verify exact version and parameter expectations

### Tertiary Hypothesis: Build Context Issues
- **Evidence:** Changes not reflected despite clean rebuilds
- **Mechanism:** Docker build context not picking up latest source
- **Validation:** Need to verify Dockerfile COPY commands and build context

## Investigation Timeline

### Attempts Made
1. **Multiple API Syntax Changes:** Positional → Object parameters
2. **Clean Rebuilds:** `docker build --no-cache` (5+ attempts)
3. **Cache Cleanup:** `docker system prune -af`, `minikube ssh -- docker system prune -af`
4. **Image Management:** `minikube image rm`, `minikube image load`
5. **Source Verification:** Confirmed line 73 contains `listNamespace()` call

### Results
- ✅ Backend runs successfully in test mode
- ✅ Emulator pod operational
- ✅ Health checks passing
- ❌ Production discovery still fails with same error
- ❌ Line number mismatch persists

## Action Plan

### Immediate Actions (Next 30 minutes)
1. **Complete Build Verification**
   - Verify Docker build context includes latest source
   - Check Dockerfile COPY commands
   - Validate image layers contain expected files

2. **API Client Investigation**
   - Check @kubernetes/client-node version in package.json
   - Verify parameter syntax for current version
   - Test API calls in isolation

3. **Deployment Pipeline Validation**
   - Verify Helm chart uses correct image tag
   - Check ImagePullPolicy is Always
   - Validate Minikube image loading process

### Short-term Actions (Next 2 hours)
1. **Complete Container Rebuild**
   - Delete all images and containers
   - Rebuild from scratch with verification
   - Deploy with fresh Minikube cluster if needed

2. **API Client Replacement**
   - Consider alternative Kubernetes client libraries
   - Implement manual REST API calls as fallback
   - Add comprehensive logging for all API calls

### Contingency Plan
If issue persists after systematic rebuild:
1. **Implement REST API Fallback:** Direct HTTP calls to Kubernetes API
2. **Static Configuration Override:** Use config files instead of discovery
3. **Alternative Discovery Method:** Service mesh or external registry

## Metrics and Success Criteria

### Success Metrics
- ✅ `kubectl logs` shows no API parameter errors
- ✅ Backend discovers emulator instances via Kubernetes API
- ✅ `ALLOW_EMPTY_DISCOVERY=false` works in production
- ✅ Real-time pod discovery functional

### Validation Tests
1. Deploy with discovery enabled
2. Verify instance enumeration
3. Confirm WebRTC streaming works
4. Test pod scaling scenarios

## Next Steps

1. **Execute development cycle script** (to be created)
2. **Systematic build verification**
3. **API client investigation**
4. **Production deployment validation**

## Updates Log

### 2025-08-14 Initial Analysis
- Documented current state and hypotheses
- Identified build/deployment inconsistency as primary suspect
- Established systematic investigation plan

---
**Note:** This document will be updated with each iteration until resolution. All investigation steps and results should be documented here for future reference.
