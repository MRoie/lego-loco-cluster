# CI Testing Tasks and Status

This document tracks the current status of CI pipeline fixes and what needs to be resolved to achieve a fully working CI system.

## Current CI Issues (As of Latest Failed Run: b49e09e)

### **CRITICAL: Minikube CPU Requirements**
- **Status**: ❌ FAILING ALL CLUSTER TESTS  
- **Issue**: Minikube requires minimum 2 CPUs but our scripts use `--cpus=1`
- **Error**: `RSRC_INSUFFICIENT_CORES: Requested cpu count 1 is less than the minimum allowed of 2`
- **Affected Jobs**: integration-network, integration-tcp, integration-broadcast, comprehensive-monitoring, e2e-live
- **Fix Required**: Update `scripts/create_minikube_cluster.sh` line 51 from `--cpus=1` to `--cpus=2`

### **Working Components** ✅
- **build**: Node.js dependency installation and frontend builds work correctly
- **e2e**: Basic WebSocket tests pass without cluster dependency
- **Docker daemon startup**: Enhanced error handling and timeouts work well
- **Script permissions**: Executable scripts and proper PATH management implemented

## Previous Fixes Applied

### **Docker Daemon Management** ✅ FIXED
- **Issue**: Docker daemon startup failures in container environments
- **Solution**: Added proper startup validation with 60s timeout, error logging
- **Commit**: b49e09e - Enhanced Docker daemon startup reliability

### **Sudo Dependencies** ✅ FIXED
- **Issue**: CI container environments don't support sudo commands
- **Solution**: Removed sudo dependencies from minikube installation process
- **Commit**: c141d4d - Removed sudo dependency from minikube install

### **WebSocket Test Endpoints** ✅ FIXED
- **Issue**: Tests were using non-existent `/signal` endpoint
- **Solution**: Fixed to use correct `/active` endpoint for stream validation
- **Commit**: c141d4d - Fixed WebSocket test endpoint

### **Enhanced Resource Management** ✅ ADDED
- **Issue**: Fixed resource requirements needed better management
- **Solution**: Added environment detection and validation
- **Features**: 
  - Automatic CI environment detection
  - System resource validation before cluster start
  - Retry logic with exponential backoff for cluster failures
  - Better diagnostic information and cleanup on failures
- **Commit**: Current - Enhanced minikube cluster creation reliability

## High Priority Fixes Needed

### 1. **CPU Allocation Fix** ✅ FIXED
```bash
# Previous (BROKEN):
--cpus=1

# Current (FIXED):
--cpus="$MINIKUBE_CPUS"  # Defaults to 2 in CI, configurable
```
**Status**: ✅ FIXED - Updated `scripts/create_minikube_cluster.sh`
**Impact**: Should resolve ALL cluster-based testing failures
**Files**: `scripts/create_minikube_cluster.sh`
**Added Features**: 
- Environment-specific resource allocation (CI vs development)
- System resource validation before cluster creation
- Retry logic with exponential backoff
- Better error diagnostics and cleanup

### 2. **Cluster Startup Reliability**
- Add better retry logic for minikube start failures
- Implement graceful fallback for resource-constrained environments
- Validate cluster requirements before attempting start

### 3. **Test Environment Detection**
- Implement CI environment detection to adjust resource requirements
- Add environment-specific configuration for different CI platforms
- Consider alternative lightweight Kubernetes solutions for CI

## Test Standards and Requirements

### **Reliability Requirements**
- Tests must pass consistently in container environments
- No flaky tests that fail intermittently
- Proper cleanup of resources after test completion
- Clear error messages and debugging information

### **Performance Requirements**
- Tests should complete within timeout limits (10-20 minutes)
- Efficient resource usage (CPU, memory, disk)
- Minimal container image requirements

### **Compatibility Requirements**
- Work in privileged container environments
- Compatible with GitHub Actions runners
- Support for both x86_64 and ARM64 architectures (future)

## Monitoring and Validation

### **CI Pipeline Health Metrics**
- Build job success rate: 100% ✅
- Integration tests success rate: 0% ❌ (blocked by CPU issue)  
- End-to-end tests success rate: 100% ✅
- Comprehensive monitoring tests: 0% ❌ (blocked by CPU issue)

### **Recovery Steps**
1. Fix CPU allocation in minikube cluster script
2. Validate all integration tests pass with 2 CPU allocation
3. Monitor for any new resource constraint issues
4. Document working CI configuration for future reference

## Next Steps

### **Immediate (This PR)**
- [x] Fix CPU allocation in `create_minikube_cluster.sh`
- [x] Add environment detection for CI-specific settings
- [x] Implement better error handling and recovery  
- [x] Add comprehensive logging for debugging
- [ ] Test cluster creation with 2 CPUs in CI
- [ ] Validate all integration tests pass

### **Short Term**
- [x] Add environment detection for CI-specific settings
- [x] Implement better error handling and recovery
- [x] Add comprehensive logging for debugging
- [ ] Create test environment validation script
- [ ] Add resource constraint fallback mechanisms

### **Long Term**
- [ ] Consider K3s or Kind as lightweight alternatives to minikube
- [ ] Implement parallel test execution for faster CI
- [ ] Add performance benchmarking to CI pipeline
- [ ] Create automated CI configuration validation

## Historical Context

The CI pipeline has evolved through several iterations:
1. **Original Talos-based**: Too resource intensive for CI
2. **Minikube transition**: Better for CI but initial resource issues
3. **Container optimization**: Improved Docker handling and dependency management
4. **Current state**: All issues resolved except CPU minimum requirements

The current fix should complete the transition to a fully working CI system suitable for container environments.