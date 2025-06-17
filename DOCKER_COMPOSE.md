# Lego Loco Cluster - Docker Compose Setup

This directory contains Docker Compose configurations for running the Lego Loco cluster locally for development and testing.

## Quick Start

### Prerequisites
- Docker and Docker Compose installed
- At least 8GB RAM available
- Linux host with TAP/TUN support (for emulator networking)

### Start Development Environment
```bash
# Setup prerequisites and start with 3 emulators
./docker-compose.sh up dev

# Start with all 9 emulators
./docker-compose.sh up dev --full
```

### Start Production Environment
```bash
# Start production setup with all 9 emulators
./docker-compose.sh up prod
```

## Configuration Files

| File | Description |
|------|-------------|
| `docker-compose.yml` | Main compose file with all services |
| `docker-compose.override.yml` | Development overrides (auto-loaded) |
| `docker-compose.prod.yml` | Production configuration |
| `docker-compose.minimal.yml` | Minimal setup for testing |
| `.env.example` | Environment variables template |

## Services

### Core Services
- **Frontend** (`localhost:3000`) - React web interface
- **Backend** (`localhost:3001`) - Node.js API server with VNC proxy
- **Registry** (`localhost:5500`) - Local Docker registry

### Emulator Services
- **Emulator 0-8** - QEMU Windows 98 instances
  - VNC: `localhost:5901-5909`
  - Web VNC: `localhost:6080-6088`
  - Video Stream: `localhost:7000-7008`

## Port Mapping

| Service | VNC Port | Web VNC | Video Stream |
|---------|----------|---------|--------------|
| Emulator 0 | 5901 | 6080 | 7000 |
| Emulator 1 | 5902 | 6081 | 7001 |
| Emulator 2 | 5903 | 6082 | 7002 |
| Emulator 3 | 5904 | 6083 | 7003 |
| Emulator 4 | 5905 | 6084 | 7004 |
| Emulator 5 | 5906 | 6085 | 7005 |
| Emulator 6 | 5907 | 6086 | 7006 |
| Emulator 7 | 5908 | 6087 | 7007 |
| Emulator 8 | 5909 | 6088 | 7008 |

## Management Commands

```bash
# Start services
./docker-compose.sh up [dev|prod] [--full] [--no-build] [--pull]

# Stop services
./docker-compose.sh down

# View logs
./docker-compose.sh logs [service]

# Check status
./docker-compose.sh status

# Restart services
./docker-compose.sh restart [service]

# Setup prerequisites
./docker-compose.sh setup

# Clean everything
./docker-compose.sh clean
```

## Development Features

### Hot Reload
In development mode:
- Frontend: Vite dev server with hot reload
- Backend: Nodemon for automatic restarts
- Source code mounted as volumes

### Minimal Setup
For quick testing, use the minimal configuration:
```bash
docker-compose -f docker-compose.minimal.yml up
```

## Networking

### TAP Bridge
The emulators use a shared TAP bridge (`loco-br`) for networking:
- Bridge IP: `192.168.10.1/24`
- Each emulator gets a TAP interface (`tap0-tap8`)
- Enables LAN gameplay between emulator instances

### Docker Network
All services run on a custom bridge network (`loco-network`):
- Subnet: `172.20.0.0/16`
- Allows inter-service communication

## Resource Requirements

### Development (3 emulators)
- RAM: ~4-6GB
- CPU: 2-4 cores
- Disk: ~2GB

### Production (9 emulators)
- RAM: ~8-12GB
- CPU: 4-8 cores
- Disk: ~4GB

## Troubleshooting

### Common Issues

1. **Permission denied accessing /dev/net/tun**
   ```bash
   sudo modprobe tun
   sudo chmod 666 /dev/net/tun
   ```

2. **TAP bridge setup fails**
   ```bash
   ./docker-compose.sh setup
   # or manually:
   sudo ./scripts/setup_bridge.sh
   ```

3. **Emulator fails to start**
   - Check if Windows 98 image exists: `ls -la images/win98.qcow2`
   - Download image: `./scripts/download_and_run_qemu.sh`

4. **Out of memory**
   - Use minimal setup: `docker-compose -f docker-compose.minimal.yml up`
   - Or dev mode with fewer emulators: `./docker-compose.sh up dev`

### Logs
View logs for specific services:
```bash
./docker-compose.sh logs frontend
./docker-compose.sh logs backend
./docker-compose.sh logs emulator-0
```

### Resource Monitoring
```bash
./docker-compose.sh status
# or
docker stats
```

## Environment Variables

Copy `.env.example` to `.env` and customize:

```bash
cp .env.example .env
# Edit .env file with your preferences
```

Key variables:
- `NODE_ENV`: development/production
- `USE_PREBUILT_SNAPSHOT`: true/false
- `SNAPSHOT_REGISTRY`: Registry URL for snapshots
- `DEBUG`: Enable debug logging

## Integration with Kubernetes

The Docker Compose setup mirrors the Kubernetes deployment:
- Same container images
- Same port mappings
- Same environment variables
- Same networking concepts

You can develop locally with Docker Compose and deploy to Kubernetes using the Helm charts in `helm/loco-chart/`.

## Security Notes

### Development
- No authentication required
- All ports exposed on localhost
- Privileged containers for TAP networking

### Production
- Consider adding authentication
- Use reverse proxy for external access
- Limit resource usage
- Regular security updates
