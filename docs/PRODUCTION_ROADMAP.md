# Production Roadmap: Lego Loco Cluster

This document outlines the comprehensive steps required to take the Lego Loco Cluster from an MVP to a production-grade deployable service.

**Last Updated**: 2025-12-01  
**Status**: In Progress  
**Current Phase**: Phase 1 (Local Development)

---

## Phase 1: Local Development & Verification ✅ (In Progress)

**Goal**: Verify core functionality in Minikube environment  
**Timeline**: Week 1-2  
**Status**: 80% Complete

### Tasks

- [x] **Install Prerequisites**: `minikube`, `kubectl`, `helm` installed and verified
- [x] **Local Cluster Setup**: Minikube cluster running with proper resources
- [/] **Verify Functionality**: 
  - [x] 1 emulator instance running and streaming
  - [x] Frontend accessible and displaying instances
  - [x] Backend API responding
  - [ ] Scale to 9 replicas (blocked by discovery issue)
- [x] **Verify VR**: VR frontend tested locally
- [x] **Fix Critical Issues**:
  - [x] Backend Dockerfile and logger paths
  - [x] Emulator resource limits (OOMKilled fix)
  - [x] RBAC permissions for backend
  - [x] Backend environment configuration
- [ ] **Service Discovery Migration**: See [Phase 2.3](#23-service-discovery-migration-critical)

**Blockers**: 
- Service discovery issue prevents scaling beyond 1 replica
- Requires migration to Endpoints-based discovery (see Phase 2.3)

**Deliverables**:
- ✅ Working Minikube deployment
- ✅ Deployment walkthrough documentation
- ⏳ Service discovery architecture review

---

## Phase 2: Infrastructure & Deployment

**Goal**: Production-ready infrastructure and deployment automation  
**Timeline**: Week 3-6  
**Status**: Not Started

### 2.1 Cloud Provider Setup

- [ ] **Cloud Provider Selection**: Choose AWS/GCP/Azure or bare metal
- [ ] **Network Architecture**: Design VPC, subnets, load balancers
- [ ] **DNS Configuration**: Set up domain and SSL certificates
- [ ] **Cost Estimation**: Calculate infrastructure costs
- [ ] **Resource Planning**: Size nodes for 9+ emulator instances

**Estimated Time**: 3 days

### 2.2 Infrastructure as Code (IaC)

- [ ] **Terraform/Pulumi Setup**: Initialize IaC repository
- [ ] **Cluster Provisioning**: Automate Kubernetes cluster creation
- [ ] **Networking**: VPC, subnets, security groups
- [ ] **Storage**: Persistent volumes, NFS/EFS setup
- [ ] **State Management**: Configure remote state backend

**Estimated Time**: 5 days

### 2.3 Service Discovery Migration (CRITICAL)

**Priority**: HIGH - Blocks scaling to 9 instances  
**Reference**: `docs/wip/SERVICE_DISCOVERY_ARCHITECTURE.md`, `docs/wip/SERVICE_DISCOVERY_TASKS.md`

#### Phase 1: Endpoints-Based Discovery (Week 1)
- [ ] **SD-001**: Create `EndpointsDiscovery` service class
- [ ] **SD-002**: Add Endpoints watch support
- [ ] **SD-003**: Update Helm chart service configuration
- [ ] **SD-004**: Add discovery mode configuration
- [ ] **SD-005**: Update InstanceManager with discovery mode
- [ ] **SD-006**: Add RBAC permissions for Endpoints API
- [ ] **SD-007**: Write unit tests for EndpointsDiscovery
- [ ] **SD-008**: Integration test in Minikube

#### Phase 2: Frontend Integration (Week 2)
- [ ] **SD-009**: Create `/api/instances/live` endpoint
- [ ] **SD-010**: Update frontend API client
- [ ] **SD-011**: Update frontend state management
- [ ] **SD-012**: Add discovery status indicator
- [ ] **SD-013**: Handle instance state transitions
- [ ] **SD-014**: Frontend integration tests
- [ ] **SD-015**: End-to-end scaling test

#### Phase 3: Advanced Features (Week 3)
- [ ] **SD-016**: Implement connection pool
- [ ] **SD-017**: Add health check aggregation
- [ ] **SD-018**: Implement EndpointSlices support
- [ ] **SD-019**: Add topology-aware routing
- [ ] **SD-020**: Add Prometheus metrics for discovery
- [ ] **SD-021**: Performance testing at scale

#### Phase 4: Migration & Cleanup (Week 4)
- [ ] **SD-022**: Update documentation
- [ ] **SD-023**: Update Minikube values to default Endpoints
- [ ] **SD-024**: Production canary deployment
- [ ] **SD-025**: Remove pod-based discovery code
- [ ] **SD-026**: Remove discovery mode feature flag
- [ ] **SD-027**: Final integration tests
- [ ] **SD-028**: Production validation

**Estimated Time**: 16 days (4 weeks)  
**Success Criteria**:
- Discovery latency <50ms
- 100% instance accuracy
- Zero downtime during migration
- Scale to 9 instances successfully

### 2.4 CI/CD Pipeline

- [ ] **Container Registry**: Configure GHCR or private registry
- [ ] **Build Automation**: 
  - [ ] Automate backend image builds
  - [ ] Automate frontend image builds
  - [ ] Automate emulator image builds
- [ ] **Deployment Automation**:
  - [ ] Helm chart deployment pipeline
  - [ ] Environment-specific configurations
  - [ ] Rollback procedures
- [ ] **GitOps Implementation**:
  - [ ] Set up ArgoCD or Flux
  - [ ] Configure auto-sync policies
  - [ ] Set up notifications

**Estimated Time**: 5 days

---

## Phase 3: Security (DevSecOps)

**Goal**: Implement security best practices  
**Timeline**: Week 7-9  
**Status**: Not Started

### 3.1 Container Security

- [ ] **Image Scanning**: 
  - [ ] Integrate Trivy/Clair in CI pipeline
  - [ ] Set vulnerability thresholds
  - [ ] Automate security reports
- [ ] **Base Image Hardening**:
  - [ ] Use distroless/minimal base images where possible
  - [ ] Remove unnecessary packages
  - [ ] Update to latest secure versions
- [ ] **Non-Root Containers**:
  - [ ] Run backend as non-root user
  - [ ] Run frontend as non-root user
  - [ ] Configure emulator security context

**Estimated Time**: 4 days

### 3.2 Network Security

- [ ] **Network Policies**:
  - [ ] Restrict backend-to-emulator traffic
  - [ ] Restrict frontend-to-backend traffic
  - [ ] Deny all by default, allow explicitly
- [ ] **Service Mesh** (Optional):
  - [ ] Evaluate Istio/Linkerd
  - [ ] Implement mTLS for service-to-service
  - [ ] Configure traffic policies
- [ ] **Ingress Security**:
  - [ ] Configure TLS/SSL certificates
  - [ ] Implement rate limiting
  - [ ] Add WAF rules

**Estimated Time**: 5 days

### 3.3 Access Control & Secrets

- [ ] **RBAC Hardening**:
  - [ ] Review and minimize service account permissions
  - [ ] Implement least privilege principle
  - [ ] Audit RBAC policies
- [ ] **Authentication**:
  - [ ] Implement OAuth/OIDC for frontend
  - [ ] Configure identity provider
  - [ ] Set up user roles
- [ ] **Secret Management**:
  - [ ] Deploy External Secrets Operator or Sealed Secrets
  - [ ] Migrate plain secrets to encrypted storage
  - [ ] Rotate secrets regularly

**Estimated Time**: 4 days

---

## Phase 4: Observability (SRE)

**Goal**: Comprehensive monitoring, logging, and alerting  
**Timeline**: Week 10-12  
**Status**: Not Started

### 4.1 Metrics & Monitoring

- [ ] **Prometheus Deployment**:
  - [ ] Deploy Prometheus Operator
  - [ ] Configure service monitors
  - [ ] Set up persistent storage
- [ ] **Grafana Dashboards**:
  - [ ] QEMU health dashboard
  - [ ] Node metrics dashboard
  - [ ] Application performance dashboard
  - [ ] **Service discovery metrics dashboard** (from SD-020)
- [ ] **Custom Metrics**:
  - [ ] Emulator frame rate metrics
  - [ ] Stream quality metrics
  - [ ] Discovery performance metrics
  - [ ] Connection pool statistics

**Estimated Time**: 5 days

### 4.2 Logging

- [ ] **Centralized Logging**:
  - [ ] Deploy Loki/ELK/Splunk
  - [ ] Configure log aggregation
  - [ ] Set up log retention policies
- [ ] **Structured Logging**:
  - [ ] Implement structured logging in backend
  - [ ] Add correlation IDs
  - [ ] Include context in all logs
- [ ] **Log Analysis**:
  - [ ] Create log queries for common issues
  - [ ] Set up log-based alerts
  - [ ] Configure log sampling for high-volume logs

**Estimated Time**: 4 days

### 4.3 Tracing & Alerting

- [ ] **Distributed Tracing**:
  - [ ] Deploy OpenTelemetry/Jaeger
  - [ ] Instrument backend services
  - [ ] Trace frontend-to-backend-to-emulator flows
- [ ] **Alerting**:
  - [ ] Set up AlertManager
  - [ ] Configure critical alerts (instance down, high latency)
  - [ ] Set up notification channels (Slack/PagerDuty)
  - [ ] Define on-call procedures

**Estimated Time**: 4 days

---

## Phase 5: Performance & Reliability

**Goal**: Optimize performance and ensure reliability  
**Timeline**: Week 13-15  
**Status**: Not Started

### 5.1 Resource Management

- [ ] **Resource Requests & Limits**:
  - [x] Define limits for emulator (completed in Phase 1)
  - [x] Define limits for backend (completed in Phase 1)
  - [ ] Define limits for frontend
  - [ ] Tune based on actual usage
- [ ] **Autoscaling**:
  - [ ] Implement HPA for backend
  - [ ] Implement HPA for frontend
  - [ ] Configure VPA for recommendations
  - [ ] Test autoscaling behavior

**Estimated Time**: 3 days

### 5.2 Load Testing

- [ ] **Test Scenarios**:
  - [ ] Simulate 9+ active users
  - [ ] Test high frame rate scenarios
  - [ ] Test rapid scaling (1→9→1)
  - [ ] Test discovery performance at scale (from SD-021)
- [ ] **Benchmark Results**:
  - [ ] Document codec performance
  - [ ] Document network throughput
  - [ ] Document discovery latency
  - [ ] Identify bottlenecks

**Estimated Time**: 4 days

### 5.3 Chaos Engineering

- [ ] **Chaos Tests**:
  - [ ] Random pod deletion
  - [ ] Node failure simulation
  - [ ] Network partition tests
  - [ ] Resource exhaustion tests
- [ ] **Resilience Validation**:
  - [ ] Verify auto-recovery
  - [ ] Verify discovery updates during failures
  - [ ] Verify zero data loss
  - [ ] Document failure scenarios

**Estimated Time**: 3 days

---

## Phase 6: Feature Completeness

**Goal**: Implement remaining features from roadmap  
**Timeline**: Week 16-18  
**Status**: Not Started

### 6.1 Input Proxy Service

- [ ] **Go WebSocket Service**:
  - [ ] Implement input proxy in Go
  - [ ] Handle QMP input forwarding
  - [ ] Add input validation
  - [ ] Performance testing

**Estimated Time**: 5 days  
**Reference**: `docs/FUTURE_TASKS.md`

### 6.2 Alternative Streaming Protocols

- [ ] **Sunshine Support**:
  - [ ] Integrate Sunshine streaming
  - [ ] Configure codec options
  - [ ] Test with various clients
- [ ] **Parsec Support**:
  - [ ] Integrate Parsec streaming
  - [ ] Configure authentication
  - [ ] Test performance

**Estimated Time**: 7 days  
**Reference**: `docs/FUTURE_TASKS.md`

### 6.3 Stream Quality Improvements

- [ ] **Quality-Adaptive Streaming**:
  - [ ] Implement bandwidth detection
  - [ ] Dynamic quality adjustment
  - [ ] User quality preferences
- [ ] **Advanced WebRTC Stats**:
  - [ ] Collect detailed WebRTC metrics
  - [ ] Create quality dashboard
  - [ ] Implement quality alerts

**Estimated Time**: 5 days

---

## Timeline Summary

| Phase | Duration | Dependencies | Status |
|-------|----------|--------------|--------|
| Phase 1: Local Development | 2 weeks | None | 80% Complete |
| Phase 2: Infrastructure | 6 weeks | Phase 1 | Not Started |
| Phase 3: Security | 3 weeks | Phase 2 | Not Started |
| Phase 4: Observability | 3 weeks | Phase 2 | Not Started |
| Phase 5: Performance | 3 weeks | Phase 2, 4 | Not Started |
| Phase 6: Features | 3 weeks | Phase 1 | Not Started |
| **Total** | **20 weeks** | - | **8% Complete** |

---

## Critical Path

The following items are on the critical path and must be completed in order:

1. **Service Discovery Migration** (Phase 2.3) - BLOCKING SCALE
2. **Cloud Infrastructure** (Phase 2.1, 2.2) - BLOCKING PRODUCTION
3. **CI/CD Pipeline** (Phase 2.4) - BLOCKING AUTOMATION
4. **Monitoring** (Phase 4.1) - BLOCKING PRODUCTION DEPLOYMENT
5. **Security Hardening** (Phase 3) - BLOCKING PUBLIC ACCESS

---

## Success Criteria

### Technical Metrics
- ✅ 9 emulator instances running simultaneously
- ⏳ <50ms service discovery latency
- ⏳ 99.9% uptime SLA
- ⏳ <100ms p95 API response time
- ⏳ Zero security vulnerabilities (critical/high)

### Business Metrics
- ⏳ Production deployment completed
- ⏳ Automated CI/CD pipeline operational
- ⏳ Comprehensive monitoring and alerting
- ⏳ Documentation complete and up-to-date

---

## Risk Register

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| Service discovery blocks scaling | High | High | **IN PROGRESS**: Endpoints-based discovery implementation |
| Cloud costs exceed budget | High | Medium | Cost estimation in Phase 2.1, set up billing alerts |
| Performance degradation at scale | High | Medium | Load testing in Phase 5.2, autoscaling in Phase 5.1 |
| Security vulnerabilities | Critical | Low | Image scanning in Phase 3.1, regular audits |
| Data loss during migration | High | Low | Backup strategy, canary deployments |

---

## Next Steps

1. ✅ Complete Phase 1 local verification
2. **🔥 IMMEDIATE**: Begin Phase 2.3 (Service Discovery Migration)
   - Start with SD-001: Create EndpointsDiscovery service
   - Target: Complete Phase 1 of discovery migration this week
3. Plan Phase 2.1 (Cloud Provider Setup)
4. Set up project tracking for all tasks
5. Assign team members to phases

---

## References

- [Service Discovery Architecture](docs/wip/SERVICE_DISCOVERY_ARCHITECTURE.md)
- [Service Discovery Tasks](docs/wip/SERVICE_DISCOVERY_TASKS.md)
- [Architecture Overview](docs/ARCHITECTURE.md)
- [Future Tasks](docs/FUTURE_TASKS.md)
- [Monitoring Guide](docs/MONITORING.md)
- [Contributing Guide](docs/CONTRIBUTING.md)
