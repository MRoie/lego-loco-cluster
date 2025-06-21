# QEMU Scripts Consolidation

This document describes the consolidation of multiple QEMU scripts into a single unified `qemu-manager.sh` script.

## Scripts Consolidated

The following scripts have been consolidated into `qemu-manager.sh`:

### VM Operation Scripts
- `build_win98_vm.sh` → `qemu-manager.sh build`
- `run-qemu.sh` → `qemu-manager.sh run` 
- `run_debug_vm.sh` → `qemu-manager.sh run-debug`
- `run_combined_vm.sh` → `qemu-manager.sh run` (with modifications)
- `run_compatible_vm.sh` → `qemu-manager.sh run` (compatibility mode)
- `run_files_vm.sh` → `qemu-manager.sh run-file-transfer`
- `run_transfer_vm.sh` → `qemu-manager.sh run-file-transfer`
- `run_fixed_vm.sh` → `qemu-manager.sh run` (with fixes)
- `run_combined_raw.sh` → `qemu-manager.sh run` (raw image support)
- `run_primary_slave.sh` → `qemu-manager.sh run` (primary/slave modes)

### File Injection Scripts
- `inject_files.sh` → `qemu-manager.sh inject-mount`
- `simple_inject.sh` → `qemu-manager.sh inject-simple`
- `pure_inject.sh` → `qemu-manager.sh inject-direct`
- `ultimate_inject.sh` → `qemu-manager.sh inject-direct`
- `direct_inject.sh` → `qemu-manager.sh inject-direct`
- `inject_nbd.sh` → `qemu-manager.sh inject-nbd`
- `copy_files_to_vm.sh` → `qemu-manager.sh inject-simple`
- `quick_transfer.sh` → `qemu-manager.sh create-transfer-iso`

### Disk Management Scripts
- `mount_qcow2.sh` → `qemu-manager.sh mount/unmount`
- `mount_vm_image.sh` → `qemu-manager.sh mount`
- `fix_disk.sh` → `qemu-manager.sh fix-disk`
- `fix_disk_access.sh` → `qemu-manager.sh fix-disk`
- `fix_disk_detection.sh` → `qemu-manager.sh fix-disk`
- `simple_disk.sh` → `qemu-manager.sh mount`

### Network and Utility Scripts
- `setup_network.sh` → `qemu-manager.sh setup-network`
- `transfer_files.sh` → `qemu-manager.sh create-transfer-iso`

## New Unified Interface

The new `qemu-manager.sh` script provides a single interface for all operations:

```bash
# VM Operations
./qemu-manager.sh build                    # Build VM from ISO
./qemu-manager.sh run                      # Run VM normally
./qemu-manager.sh run-debug               # Run with debug console
./qemu-manager.sh run-file-transfer       # Run with file transfer

# File Injection
./qemu-manager.sh inject-simple           # ISO-based injection
./qemu-manager.sh inject-direct           # libguestfs injection
./qemu-manager.sh inject-mount            # Mount-based injection
./qemu-manager.sh create-transfer-iso     # Create transfer ISO

# Disk Management
./qemu-manager.sh mount                   # Mount qcow2 image
./qemu-manager.sh unmount                 # Unmount image
./qemu-manager.sh fix-disk               # Fix disk issues

# Utilities
./qemu-manager.sh status                  # Show system status
./qemu-manager.sh backup                  # Create backup
./qemu-manager.sh cleanup                 # Clean up temp files
./qemu-manager.sh check-prereqs          # Check dependencies
```

## Benefits of Consolidation

1. **Single Entry Point**: One script handles all VM operations
2. **Consistent Interface**: Unified command structure and logging
3. **Better Error Handling**: Comprehensive error checking and reporting
4. **Dependency Management**: Automatic prerequisite checking
5. **Status Monitoring**: Built-in status and health checking
6. **Cleanup Management**: Automated cleanup of resources
7. **Documentation**: Built-in help and usage information

## Migration Guide

### Old Script → New Command Mapping

| Old Script | New Command |
|------------|-------------|
| `./build_win98_vm.sh` | `./qemu-manager.sh build` |
| `./run-qemu.sh` | `./qemu-manager.sh run` |
| `./inject_files.sh full` | `./qemu-manager.sh inject-mount` |
| `./simple_inject.sh create-iso` | `./qemu-manager.sh create-transfer-iso` |
| `./mount_qcow2.sh mount` | `./qemu-manager.sh mount` |
| `./setup_network.sh` | `./qemu-manager.sh setup-network` |

### Preserved Functionality

All original functionality has been preserved and enhanced:

- **VM Building**: Complete Windows 98 installation process
- **File Injection**: Multiple methods (ISO, direct, mount-based)
- **Network Setup**: Bridge and TAP interface configuration  
- **Disk Management**: Mount, unmount, repair operations
- **Debug Support**: Debug console and logging
- **Backup/Restore**: Image backup and restoration

### New Features Added

- **Status Monitoring**: Real-time system status checking
- **Dependency Checking**: Automatic prerequisite validation
- **Better Logging**: Color-coded output with different log levels
- **Resource Cleanup**: Automatic cleanup of processes and resources
- **Error Recovery**: Better error handling and recovery options
- **Backup Management**: Automated backup creation with timestamps

## Configuration

All configuration is centralized at the top of `qemu-manager.sh`:

```bash
# File Configuration
WIN98_ISO="win98.iso"
SOFTGPU_ISO="softgpu.iso"
QCOW2_IMAGE="win98_softgpu.qcow2"

# VM Configuration  
RAM_MB=768
CPU_CORES=1
VNC_DISPLAY=0
```

## Backward Compatibility

The old scripts are preserved in the `old-scripts/` directory for reference and can be moved back if needed. However, the new consolidated script should handle all use cases more reliably.

## Future Enhancements

The consolidated script provides a foundation for:

1. **Configuration Profiles**: Different VM configurations for different use cases
2. **Automated Testing**: Built-in testing and validation
3. **Container Integration**: Better Docker/Kubernetes integration
4. **Remote Management**: Web interface for VM management
5. **Snapshot Management**: VM state snapshot and restoration
