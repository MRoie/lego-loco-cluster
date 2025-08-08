# Lego Loco Cluster Development Instructions

**ALWAYS follow these instructions first before searching or running additional commands.** Only search for additional information if these instructions are incomplete or contain errors.

## Repository Overview
Lego Loco Cluster runs multiple Windows 98 emulator instances with Lego Loco game in Docker/Kubernetes with WebRTC streaming. The web dashboard provides 3×3 grid of streams with audio, keyboard, and mouse control, plus an optional VR viewer.

**Key Components:**
- **Backend**: Node.js Express server with WebSocket signaling (port 3001)
- **Frontend**: React with Vite dev server (port 3000) 
- **VR Frontend**: A-Frame based VR interface (port 3002)
- **Emulators**: Dockerized Windows 98 QEMU instances with VNC ports 5901-5909
- **Registry**: Local Docker registry (port 5500, was 5000 to avoid GStreamer conflicts)

## Environment Setup

**CRITICAL**: Install system dependencies first. This takes **2-3 minutes**:
```bash
sudo apt-get update  # Takes ~7 seconds
sudo apt-get install -y nodejs npm qemu-system-x86 qemu-kvm wine gstreamer1.0-tools pulseaudio tcpdump  # Takes ~2 minutes
```

**Note**: Skip `docker.io` if Docker is already installed to avoid conflicts.

## Build and Development Commands

### Install Dependencies
**NEVER CANCEL**: Node dependencies take time to install:
```bash
cd backend && npm install && cd ..    # Takes ~25 seconds
cd frontend && npm install && cd ..   # Takes ~3 minutes (includes git dependencies)
```

Alternative using Makefile:
```bash
make dev-install  # Takes ~2 seconds if already installed
```

### Build Frontend
**NEVER CANCEL**: Frontend build takes time:
```bash
cd frontend && npm run build  # Takes ~6 seconds, produces ~1.9MB bundle
```

Alternative using Makefile:
```bash
make dev-build-frontend  # Takes ~6 seconds
```

### Development Environment

**Primary Development Method - Individual Services:**
```bash
# Terminal 1: Start Backend (starts immediately)
cd backend && npm run start
# Backend available at http://localhost:3001
# Health check: curl http://localhost:3001/health
# API endpoint: curl http://localhost:3001/api/instances

# Terminal 2: Start Frontend (starts in ~1 second)
cd frontend && npm run dev
# Frontend available at http://localhost:3000 with hot reload
```

**Alternative - Docker Development Environment:**
```bash
# Make scripts executable first
chmod +x scripts/dev-start.sh scripts/health-check.sh

# Start development environment
./scripts/dev-start.sh  # Full environment with containers
./scripts/dev-start.sh --minimal  # Backend + Frontend only
./scripts/dev-start.sh --no-logs  # Don't follow logs

# Check health
./scripts/health-check.sh
```

**Makefile Commands:**
```bash
make help           # Show all available commands (~0.01 seconds)
make up             # Start development environment (3 emulators) 
make up-minimal     # Start minimal environment (1 emulator)
make up-full        # Start with all 9 emulators
make down           # Stop all containers
make logs           # Show all logs
make logs-backend   # Show backend logs only
make logs-frontend  # Show frontend logs only
make health         # Run health checks
make test           # Basic connectivity tests (~0.2 seconds)
```

## Validation and Testing

### Manual Validation Steps
After making changes, **ALWAYS** run these validation steps:

1. **Backend Validation**:
   ```bash
   cd backend && npm run start
   # Wait for "Backend running on http://localhost:3001"
   curl -f http://localhost:3001/health  # Should return {"status":"ok"}
   curl -s http://localhost:3001/api/instances | head -5  # Should return JSON array
   ```

2. **Frontend Validation**:
   ```bash
   cd frontend && npm run dev
   # Wait for "ready in X ms" and "Local: http://localhost:3000/"
   curl -f http://localhost:3000  # Should return HTML with React app
   ```

3. **Build Validation**:
   ```bash
   cd frontend && npm run build  # Should complete in ~6 seconds
   # Look for "built in X.XXs" message
   ```

### Test Scripts
```bash
# Test backend connectivity (requires backend running)
./k8s-tests/test-websocket.sh  # Takes ~0.2 seconds, tests API and WebSocket

# Test development environment
./tests/test-dev-environment.sh  # Comprehensive environment test
```

## Kubernetes and Cluster Testing

**WARNING**: Cluster operations take significant time. **NEVER CANCEL** these commands:

### Install Talosctl (Required for Kubernetes testing)
```bash
curl -L https://github.com/siderolabs/talos/releases/latest/download/talosctl-linux-amd64 -o talosctl  # Takes ~1 second
sudo install -m 0755 talosctl /usr/local/bin/talosctl
```

### Create Test Cluster
**CRITICAL - TIMEOUT SETTINGS**: Cluster creation takes **10+ minutes**. Use **15+ minute timeouts**:
```bash
WORKERS=1 timeout 15m ./scripts/create_cluster.sh  # Takes 10-15 minutes, NEVER CANCEL
# Creates Talos cluster with 1 worker node
```

### Cluster Tests  
**CRITICAL - TIMEOUT SETTINGS**: Set **10+ minute timeouts** for integration tests:
```bash
chmod +x k8s-tests/*.sh

# Network connectivity test (requires cluster)
./k8s-tests/test-network.sh     # Tests pod-to-pod connectivity

# TCP connectivity test  
./k8s-tests/test-tcp.sh         # Tests TCP connections

# Broadcast test
./k8s-tests/test-broadcast.sh   # Tests broadcast functionality

# Cleanup cluster
talosctl cluster destroy --name loco
```

## File Structure and Key Locations

### Frequently Modified Files
- `backend/server.js` - Main backend server
- `backend/package.json` - Backend dependencies
- `frontend/src/` - React frontend source
- `frontend/package.json` - Frontend dependencies  
- `config/instances.json` - Emulator instance configuration
- `compose/docker-compose.yml` - Main Docker Compose file
- `helm/loco-chart/values.yaml` - Kubernetes configuration

### Configuration Files
- `.devcontainer/devcontainer.json` - Development container setup
- `compose/docker-compose.dev.yml` - Development overrides
- `compose/docker-compose.minimal.yml` - Minimal setup
- `k8s/` - Kubernetes manifests
- `kustomize/base/` - Kustomize base configuration

### Scripts Directory
- `scripts/dev-start.sh` - Development environment startup
- `scripts/health-check.sh` - Health check script  
- `scripts/create_cluster.sh` - Talos cluster creation
- `scripts/docker-compose.sh` - Docker Compose management

## Common Issues and Workarounds

### Build Issues
- **Frontend security vulnerabilities**: Run `npm audit` in frontend/ but generally safe to ignore for development
- **Large bundle warning**: Expected for React app with A-Frame, can ignore in development
- **Docker conflicts**: Use minimal compose if full setup fails: `make up-minimal`

### Port Conflicts
```bash
make cleanup-ports  # Clean up port conflicts
```

### Missing Dependencies
If commands fail:
```bash
# Re-run dependency installation
make dev-install
# Or manually:
cd backend && npm install && cd ../frontend && npm install && cd ..
```

## Production Deployment

### Helm Deployment
```bash
# Deploy to Kubernetes cluster
REPLICAS=1 ./scripts/deploy_single.sh   # Single instance
REPLICAS=3 ./scripts/deploy_single.sh   # Three instances  
REPLICAS=9 ./scripts/deploy_single.sh   # Full 3x3 grid
```

### Production Build
```bash
make env-prod        # Set production environment
make up-prod         # Start production environment
```

## Development URLs

**Always check these URLs after starting services:**
- Frontend: http://localhost:3000
- Backend: http://localhost:3001  
- Backend Health: http://localhost:3001/health
- Backend API: http://localhost:3001/api/instances
- VR Frontend: http://localhost:3002 (when running)
- Registry: http://localhost:5500
- VNC Access: vnc://localhost:5901 (first emulator)
- Web VNC: http://localhost:6080 (first emulator)

## Timing Expectations and Timeouts

**CRITICAL**: Use these timeout values in your commands:

| Operation | Expected Time | Minimum Timeout |
|-----------|---------------|-----------------|
| `apt-get update` | 7 seconds | 30 seconds |
| `apt-get install dependencies` | 2 minutes | 5 minutes |
| Backend `npm install` | 25 seconds | 60 seconds |
| Frontend `npm install` | 3 minutes | 5 minutes |
| Frontend `npm run build` | 6 seconds | 30 seconds |
| Backend startup | 1 second | 10 seconds |
| Frontend dev server startup | 1 second | 10 seconds |  
| Talosctl download | 1 second | 60 seconds |
| **Talos cluster creation** | **10-15 minutes** | **20 minutes** |
| Integration tests | 0.2 seconds | 60 seconds |
| Health checks | 0.1 seconds | 10 seconds |

**NEVER CANCEL long-running operations**. Cluster creation taking 10+ minutes is normal.

## CI/CD Integration

The repository includes GitHub Actions workflows in `.github/workflows/`:
- `ci.yml` - Main CI pipeline with build and integration tests  
- `build-qemu.yml` - QEMU container builds
- `docker-compose.yml` - Docker Compose builds
- `win98-softgpu.yml` - Windows 98 image builds

Tests run automatically on pushes to `run_ci` branch.