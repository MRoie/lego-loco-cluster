# Service Discovery Implementation Tasks

This document breaks down the Service Discovery Architecture implementation into manageable, trackable tasks organized by phase.

## Overview

**Total Phases**: 4  
**Total Tasks**: 32  
**Estimated Timeline**: 4 weeks  
**Priority**: High (blocks scaling to 9 emulators)

---

## Phase 1: Endpoints-Based Discovery (Week 1)

**Goal**: Implement Kubernetes Endpoints API discovery alongside existing Pod-based discovery  
**Deliverable**: Working endpoints discovery with feature flag  
**Estimated Effort**: 5 days

### Tasks

#### 1.1 Create EndpointsDiscovery Service
- **ID**: SD-001
- **Description**: Implement new `backend/services/endpointsDiscovery.js` class
- **Acceptance Criteria**:
  - [ ] Class implements `discoverInstances()` method
  - [ ] Correctly parses Endpoints API response
  - [ ] Returns instances with `addresses`, `ports`, and `health` fields
  - [ ] Handles both ready and not-ready addresses
  - [ ] Includes DNS name construction for each instance
- **Dependencies**: None
- **Estimated Time**: 4 hours
- **Assignee**: TBD

#### 1.2 Add Endpoints Watch Support
- **ID**: SD-002
- **Description**: Implement `watchEndpoints()` method for real-time updates
- **Acceptance Criteria**:
  - [ ] Watch established on Endpoints object
  - [ ] Callback triggered on endpoint changes
  - [ ] Graceful error handling for watch failures
  - [ ] Automatic reconnection on connection loss
- **Dependencies**: SD-001
- **Estimated Time**: 3 hours
- **Assignee**: TBD

#### 1.3 Update Helm Chart - Service Configuration
- **ID**: SD-003
- **Description**: Ensure emulator Service has `publishNotReadyAddresses: false`
- **Acceptance Criteria**:
  - [ ] `helm/loco-chart/templates/emulator-service.yaml` updated
  - [ ] Service only includes ready pods in endpoints
  - [ ] Helm chart validates successfully
- **Dependencies**: None
- **Estimated Time**: 30 minutes
- **Assignee**: TBD

#### 1.4 Add Discovery Mode Configuration
- **ID**: SD-004
- **Description**: Add `discoveryMode` configuration to Helm values
- **Acceptance Criteria**:
  - [ ] `values-minikube.yaml` includes `backend.discoveryMode` setting
  - [ ] Default value is `kubernetes-pods` (current behavior)
  - [ ] `kubernetes-endpoints` option available
  - [ ] Service name configurable via `backend.serviceDiscovery.serviceName`
- **Dependencies**: None
- **Estimated Time**: 1 hour
- **Assignee**: TBD

#### 1.5 Update InstanceManager with Discovery Mode
- **ID**: SD-005
- **Description**: Modify `instanceManager.js` to support multiple discovery modes
- **Acceptance Criteria**:
  - [ ] Reads `DISCOVERY_MODE` environment variable
  - [ ] Instantiates `EndpointsDiscovery` when mode is `kubernetes-endpoints`
  - [ ] Falls back to `KubernetesDiscovery` for `kubernetes-pods` mode
  - [ ] Logs active discovery mode on startup
- **Dependencies**: SD-001, SD-004
- **Estimated Time**: 2 hours
- **Assignee**: TBD

#### 1.6 Add RBAC Permissions for Endpoints
- **ID**: SD-006
- **Description**: Update `rbac.yaml` to grant Endpoints API access
- **Acceptance Criteria**:
  - [ ] Backend Role includes `endpoints` resource
  - [ ] Permissions include `get`, `list`, `watch` verbs
  - [ ] Optional: Add `endpointslices` for future scalability
  - [ ] RBAC validates in Minikube
- **Dependencies**: None
- **Estimated Time**: 30 minutes
- **Assignee**: TBD

#### 1.7 Unit Tests for EndpointsDiscovery
- **ID**: SD-007
- **Description**: Write comprehensive unit tests
- **Acceptance Criteria**:
  - [ ] Test `parseEndpoints()` with mock data
  - [ ] Test `createInstance()` with various pod names
  - [ ] Test `mapPorts()` with different port configurations
  - [ ] Test `extractInstanceNumber()` edge cases
  - [ ] All tests pass with >90% coverage
- **Dependencies**: SD-001
- **Estimated Time**: 4 hours
- **Assignee**: TBD

#### 1.8 Integration Test - Minikube Deployment
- **ID**: SD-008
- **Description**: Deploy to Minikube with `kubernetes-endpoints` mode
- **Acceptance Criteria**:
  - [ ] Helm chart deploys successfully
  - [ ] Backend pod starts without errors
  - [ ] Backend logs show "Using discovery mode: kubernetes-endpoints"
  - [ ] `/api/instances` endpoint returns discovered instances
  - [ ] Instances include correct DNS names and IPs
- **Dependencies**: SD-001 through SD-006
- **Estimated Time**: 2 hours
- **Assignee**: TBD

---

## Phase 2: Frontend Integration (Week 2)

**Goal**: Update frontend to use live discovery API  
**Deliverable**: Frontend displays real-time instance data from Endpoints API  
**Estimated Effort**: 3 days

### Tasks

#### 2.1 Create /api/instances/live Endpoint
- **ID**: SD-009
- **Description**: Add new backend endpoint for live instance data
- **Acceptance Criteria**:
  - [ ] Endpoint returns JSON with `instances`, `discoveryMode`, `summary`
  - [ ] Summary includes `total`, `ready`, `notReady` counts
  - [ ] Response includes `lastUpdate` timestamp
  - [ ] Endpoint responds within 100ms
- **Dependencies**: SD-005
- **Estimated Time**: 2 hours
- **Assignee**: TBD

#### 2.2 Update Frontend API Client
- **ID**: SD-010
- **Description**: Create `fetchLiveInstances()` function in frontend
- **Acceptance Criteria**:
  - [ ] Function calls `/api/instances/live`
  - [ ] Parses response correctly
  - [ ] Returns instances array and metadata
  - [ ] Includes error handling with retry logic
- **Dependencies**: SD-009
- **Estimated Time**: 1 hour
- **Assignee**: TBD

#### 2.3 Update Frontend State Management
- **ID**: SD-011
- **Description**: Modify frontend to use live discovery as primary source
- **Acceptance Criteria**:
  - [ ] `useState` hook updated to track discovery mode
  - [ ] Live discovery called on component mount
  - [ ] Polling interval set to 5 seconds
  - [ ] Static config used only as initial fallback
  - [ ] UI shows discovery mode indicator
- **Dependencies**: SD-010
- **Estimated Time**: 3 hours
- **Assignee**: TBD

#### 2.4 Add Discovery Status Indicator
- **ID**: SD-012
- **Description**: Display discovery mode and health in frontend UI
- **Acceptance Criteria**:
  - [ ] Header shows "Auto-Discovery: kubernetes-endpoints (X pods)"
  - [ ] Color-coded status (green=live, yellow=fallback, red=error)
  - [ ] Tooltip explains discovery mode
  - [ ] Updates in real-time
- **Dependencies**: SD-011
- **Estimated Time**: 2 hours
- **Assignee**: TBD

#### 2.5 Handle Instance State Transitions
- **ID**: SD-013
- **Description**: Gracefully handle instances moving between ready/not-ready
- **Acceptance Criteria**:
  - [ ] UI shows "booting" state for not-ready instances
  - [ ] Smooth transitions without flickering
  - [ ] Maintains instance order during updates
  - [ ] Shows last-seen timestamp for disappeared instances
- **Dependencies**: SD-011
- **Estimated Time**: 3 hours
- **Assignee**: TBD

#### 2.6 Frontend Integration Tests
- **ID**: SD-014
- **Description**: Write tests for live discovery integration
- **Acceptance Criteria**:
  - [ ] Test `fetchLiveInstances()` with mock responses
  - [ ] Test state updates on successful discovery
  - [ ] Test fallback to static config on error
  - [ ] Test polling interval behavior
  - [ ] All tests pass
- **Dependencies**: SD-010, SD-011
- **Estimated Time**: 3 hours
- **Assignee**: TBD

#### 2.7 End-to-End Test - Scaling Scenario
- **ID**: SD-015
- **Description**: Test frontend updates when scaling emulators
- **Acceptance Criteria**:
  - [ ] Scale emulators from 1 to 3 replicas
  - [ ] Frontend shows new instances within 10 seconds
  - [ ] Instance cards display correct status
  - [ ] No console errors during scaling
  - [ ] Scale down to 1, verify frontend updates
- **Dependencies**: SD-011, SD-012
- **Estimated Time**: 2 hours
- **Assignee**: TBD

---

## Phase 3: Advanced Features (Week 3)

**Goal**: Add production-grade features for resilience and performance  
**Deliverable**: Connection pooling, health aggregation, topology awareness  
**Estimated Effort**: 5 days

### Tasks

#### 3.1 Implement Connection Pool
- **ID**: SD-016
- **Description**: Create connection pool manager for emulator connections
- **Acceptance Criteria**:
  - [ ] Pool maintains connections to ready endpoints
  - [ ] Automatically adds new endpoints
  - [ ] Removes connections for removed endpoints
  - [ ] Implements connection health checks
  - [ ] Exposes pool statistics
- **Dependencies**: SD-009
- **Estimated Time**: 4 hours
- **Assignee**: TBD

#### 3.2 Add Health Check Aggregation
- **ID**: SD-017
- **Description**: Combine Kubernetes health with application-level health
- **Acceptance Criteria**:
  - [ ] Queries `/health` endpoint on each instance
  - [ ] Aggregates with Kubernetes readiness status
  - [ ] Includes stream quality metrics
  - [ ] Returns overall health score (0-100)
  - [ ] Caches health data with 10s TTL
- **Dependencies**: SD-009
- **Estimated Time**: 3 hours
- **Assignee**: TBD

#### 3.3 Implement EndpointSlices Support
- **ID**: SD-018
- **Description**: Add optional EndpointSlices discovery for K8s 1.21+
- **Acceptance Criteria**:
  - [ ] New `endpointSlicesDiscovery.js` class
  - [ ] Configurable via `backend.serviceDiscovery.useEndpointSlices`
  - [ ] Parses EndpointSlice objects correctly
  - [ ] Falls back to Endpoints if EndpointSlices unavailable
  - [ ] Unit tests for EndpointSlices parsing
- **Dependencies**: SD-001
- **Estimated Time**: 4 hours
- **Assignee**: TBD

#### 3.4 Add Topology-Aware Routing
- **ID**: SD-019
- **Description**: Prefer same-zone endpoints when available
- **Acceptance Criteria**:
  - [ ] Detects current zone from node metadata
  - [ ] Filters endpoints by zone when using EndpointSlices
  - [ ] Falls back to all zones if no local endpoints
  - [ ] Logs topology decisions
- **Dependencies**: SD-018
- **Estimated Time**: 3 hours
- **Assignee**: TBD

#### 3.5 Add Metrics for Discovery
- **ID**: SD-020
- **Description**: Expose Prometheus metrics for discovery operations
- **Acceptance Criteria**:
  - [ ] `discovery_instances_total` gauge
  - [ ] `discovery_instances_ready` gauge
  - [ ] `discovery_api_calls_total` counter
  - [ ] `discovery_api_duration_seconds` histogram
  - [ ] Metrics endpoint includes new metrics
- **Dependencies**: SD-009
- **Estimated Time**: 2 hours
- **Assignee**: TBD

#### 3.6 Performance Testing
- **ID**: SD-021
- **Description**: Benchmark discovery performance at scale
- **Acceptance Criteria**:
  - [ ] Test with 9 emulator replicas
  - [ ] Measure discovery latency (target: <50ms)
  - [ ] Measure watch update latency (target: <1s)
  - [ ] Test with rapid scaling (1→9→1)
  - [ ] Document performance results
- **Dependencies**: SD-015
- **Estimated Time**: 3 hours
- **Assignee**: TBD

---

## Phase 4: Migration & Cleanup (Week 4)

**Goal**: Complete migration to Endpoints-based discovery  
**Deliverable**: Production-ready discovery with legacy code removed  
**Estimated Effort**: 3 days

### Tasks

#### 4.1 Update Documentation
- **ID**: SD-022
- **Description**: Update all docs to reflect new discovery architecture
- **Acceptance Criteria**:
  - [ ] `docs/ARCHITECTURE.md` updated with discovery flow
  - [ ] `docs/MONITORING.md` includes discovery metrics
  - [ ] `README.md` mentions discovery mode configuration
  - [ ] `docs/wip/SERVICE_DISCOVERY_ARCHITECTURE.md` marked as implemented
- **Dependencies**: All Phase 3 tasks
- **Estimated Time**: 3 hours
- **Assignee**: TBD

#### 4.2 Update Minikube Values to Default Endpoints
- **ID**: SD-023
- **Description**: Change default discovery mode to `kubernetes-endpoints`
- **Acceptance Criteria**:
  - [ ] `values-minikube.yaml` sets `backend.discoveryMode: kubernetes-endpoints`
  - [ ] Deployment guide updated
  - [ ] Tested in clean Minikube cluster
- **Dependencies**: SD-021
- **Estimated Time**: 1 hour
- **Assignee**: TBD

#### 4.3 Production Canary Deployment
- **ID**: SD-024
- **Description**: Deploy to production with canary strategy
- **Acceptance Criteria**:
  - [ ] 10% of backend pods use `kubernetes-endpoints`
  - [ ] Monitor for 24 hours with no errors
  - [ ] Increase to 50% for 24 hours
  - [ ] Full rollout to 100%
  - [ ] Rollback plan documented and tested
- **Dependencies**: SD-023
- **Estimated Time**: 2 days (monitoring time)
- **Assignee**: TBD

#### 4.4 Remove Pod-Based Discovery Code
- **ID**: SD-025
- **Description**: Delete deprecated `KubernetesDiscovery` pod query logic
- **Acceptance Criteria**:
  - [ ] Remove `discoverEmulatorInstances()` pod query code
  - [ ] Remove `listNamespacedPod` calls
  - [ ] Remove StatefulSet metadata queries
  - [ ] Keep `KubernetesDiscovery` class for other K8s operations
  - [ ] All tests still pass
- **Dependencies**: SD-024
- **Estimated Time**: 2 hours
- **Assignee**: TBD

#### 4.5 Remove Discovery Mode Feature Flag
- **ID**: SD-026
- **Description**: Remove `DISCOVERY_MODE` env var, make endpoints default
- **Acceptance Criteria**:
  - [ ] Remove `discoveryMode` from Helm values
  - [ ] Remove mode selection logic from `instanceManager.js`
  - [ ] Update all references in code and docs
  - [ ] Simplify configuration
- **Dependencies**: SD-025
- **Estimated Time**: 1 hour
- **Assignee**: TBD

#### 4.6 Final Integration Tests
- **ID**: SD-027
- **Description**: Run full test suite with new discovery
- **Acceptance Criteria**:
  - [ ] All unit tests pass
  - [ ] All integration tests pass
  - [ ] End-to-end tests pass
  - [ ] Performance benchmarks meet targets
  - [ ] No regression in functionality
- **Dependencies**: SD-026
- **Estimated Time**: 2 hours
- **Assignee**: TBD

#### 4.7 Production Validation
- **ID**: SD-028
- **Description**: Verify production deployment health
- **Acceptance Criteria**:
  - [ ] All instances discovered correctly
  - [ ] Frontend shows accurate instance count
  - [ ] No discovery-related errors in logs
  - [ ] Metrics show healthy discovery operations
  - [ ] User-facing functionality unchanged
- **Dependencies**: SD-024
- **Estimated Time**: 1 hour
- **Assignee**: TBD

---

## Rollback Plan

### Immediate Rollback (If Critical Issues Found)

**Trigger**: Discovery failures, instance unavailability, or data corruption

**Steps**:
1. Set `backend.discoveryMode: kubernetes-pods` in Helm values
2. Run `helm upgrade` to revert to pod-based discovery
3. Verify instances are discovered correctly
4. Monitor for 30 minutes

**Estimated Time**: 15 minutes

### Gradual Rollback (If Performance Issues Found)

**Trigger**: High latency, resource usage, or intermittent failures

**Steps**:
1. Reduce canary percentage (100% → 50% → 10%)
2. Monitor metrics at each step
3. Identify root cause
4. Fix and re-deploy, or complete rollback

**Estimated Time**: 2-4 hours

---

## Success Metrics

### Technical Metrics
- **Discovery Latency**: <50ms (target), <100ms (acceptable)
- **Watch Update Latency**: <1s from endpoint change to backend awareness
- **API Error Rate**: <0.1%
- **Instance Accuracy**: 100% (all running instances discovered)

### Business Metrics
- **Scaling Time**: <30s from `kubectl scale` to frontend showing new instances
- **Zero Downtime**: No user-visible disruption during migration
- **Reduced Complexity**: 50% reduction in discovery-related code

---

## Dependencies & Blockers

### External Dependencies
- Kubernetes 1.19+ (for Endpoints API stability)
- Kubernetes 1.21+ (for EndpointSlices, optional)
- Helm 3.x

### Internal Dependencies
- RBAC permissions must be updated before testing
- Frontend must be updated before removing static config dependency
- Monitoring must be in place before production rollout

### Potential Blockers
- **API Version Compatibility**: Kubernetes client library version mismatch
  - *Mitigation*: Test with multiple K8s versions (1.19, 1.21, 1.28)
- **Performance at Scale**: Endpoints API may be slow with 100+ instances
  - *Mitigation*: Use EndpointSlices for large deployments
- **DNS Resolution**: CoreDNS issues could affect headless service
  - *Mitigation*: Use IP addresses from Endpoints, DNS as fallback

---

## Task Summary by Phase

| Phase | Tasks | Estimated Days | Priority |
|-------|-------|----------------|----------|
| Phase 1: Endpoints Discovery | 8 tasks (SD-001 to SD-008) | 5 days | Critical |
| Phase 2: Frontend Integration | 7 tasks (SD-009 to SD-015) | 3 days | High |
| Phase 3: Advanced Features | 6 tasks (SD-016 to SD-021) | 5 days | Medium |
| Phase 4: Migration & Cleanup | 8 tasks (SD-022 to SD-028) | 3 days | Medium |
| **Total** | **29 tasks** | **16 days** | - |

---

## Next Steps

1. **Review & Approve**: Stakeholder review of this task breakdown
2. **Assign Tasks**: Assign tasks to team members
3. **Create Tracking**: Create tickets in project management system
4. **Begin Phase 1**: Start with SD-001 (EndpointsDiscovery implementation)
5. **Daily Standups**: Track progress and blockers

---

## Notes

- Tasks can be parallelized within phases (e.g., SD-003, SD-004, SD-006 can run concurrently)
- Phase 2 cannot start until Phase 1 is complete and tested
- Phase 4 requires production approval before execution
- All code changes should be committed to feature branch `feature/endpoints-discovery`
- Each task should have a corresponding PR for review
