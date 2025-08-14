# Lego Loco 1024x768 Stream Upgrade

This commit updates all emulator containers to stream at 1024x768 resolution for optimal Lego Loco gaming experience.

## Changes Made

### Resolution Upgrade
- **Before**: 640x480 @ 500 kbps
- **After**: 1024x768 @ 1200 kbps (+2.56x pixels, +140% bitrate)

### SRE Implementation
- Added real-time stream health monitoring
- Implemented comprehensive validation functions
- Enhanced logging with resolution confirmation
- Created automated testing script for stream validation

### Files Updated
1. `containers/qemu/entrypoint.sh` - Main QEMU H.264 UDP streaming
2. `containers/qemu-bootable/entrypoint-bootable.sh` - Bootable variant H.264 streaming  
3. `containers/qemu-softgpu/entrypoint.sh` - GPU-accelerated H.264 streaming
4. `containers/pcem/entrypoint.sh` - PCem VP8 WebRTC streaming
5. `scripts/test-1024x768-streams.sh` - Real-time validation script

### Technical Details
- **GStreamer Pipeline**: Updated `video/x-raw,width=1024,height=768,framerate=25/1`
- **Bitrate Optimization**: Increased from 500 to 1200 kbps for quality
- **SRE Monitoring**: Added stream health checks and performance validation
- **Compatibility**: Maintains existing queue management and buffer optimization

### Testing
```bash
# Build and test containers
docker build -t test-qemu-1024x768 containers/qemu/
./scripts/test-1024x768-streams.sh

# Validate resolution in running containers  
docker logs <container> | grep "1024x768"
```

### Performance Impact
- **Quality**: Significantly improved visual clarity for Lego Loco
- **Bandwidth**: ~140% increase (1200 vs 500 kbps)
- **Latency**: Maintained with same encoding settings
- **Reliability**: Enhanced with SRE monitoring

This ensures the Lego Loco Cluster delivers optimal gaming experience with native resolution streaming and robust monitoring.