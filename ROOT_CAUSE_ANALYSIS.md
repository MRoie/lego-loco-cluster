# Root Cause Analysis: VNC Screenshot Failure

## Problem Statement
The current testing framework fails to capture real Windows 98 desktop screenshots via VNC, resulting in fallback status images instead of actual Windows 98 visuals.

## Root Cause Analysis Checklist

### 1. VNC Server Configuration Issues
- [ ] **QEMU VNC binding**: Currently using `vnc=0.0.0.0:1` which binds to port 5901
- [ ] **VNC authentication**: No password set in QEMU VNC configuration
- [ ] **VNC display output**: QEMU may not be directing Windows 98 output to VNC
- [ ] **VNC protocol version**: Compatibility issues between QEMU VNC and capture tools

### 2. Windows 98 Boot and Display Issues
- [ ] **Boot time insufficient**: 90 seconds may not be enough for complete Windows 98 startup
- [ ] **Display driver issues**: Windows 98 may not have proper display drivers
- [ ] **Resolution mismatch**: Windows 98 internal resolution vs VNC display resolution
- [ ] **Graphics mode**: Windows 98 may be in text mode instead of graphical mode

### 3. Container Environment Issues
- [ ] **X11 display isolation**: Xvfb display may conflict with VNC capture
- [ ] **Display number conflicts**: Multiple services using same display numbers
- [ ] **Container networking**: VNC port may not be accessible from host
- [ ] **Permission issues**: VNC tools may lack permissions to access display

### 4. VNC Client Tool Issues
- [ ] **vncsnapshot compatibility**: Tool may not work with QEMU VNC implementation
- [ ] **vncdo compatibility**: Python VNC library compatibility issues
- [ ] **Tool installation**: VNC tools may not be properly installed in CI environment
- [ ] **Authentication methods**: Tools trying wrong authentication methods

### 5. QEMU Configuration Issues
- [ ] **VGA output**: Using `-vga std` may not provide proper VNC output
- [ ] **Display redirect**: QEMU may be outputting to wrong display
- [ ] **Graphics acceleration**: Software GPU may interfere with VNC display
- [ ] **Boot sequence**: QEMU may not be booting Windows 98 properly

### 6. Timing and Synchronization Issues
- [ ] **Process startup order**: Services starting in wrong order
- [ ] **Windows 98 boot completion**: System may still be booting when screenshots taken
- [ ] **VNC server readiness**: VNC may not be ready when capture attempts start
- [ ] **Network service timing**: Port binding may not be complete

### 7. CI Environment Limitations
- [ ] **Container isolation**: VNC access restricted in CI containers
- [ ] **Network restrictions**: Port forwarding may not work in CI
- [ ] **Resource constraints**: Insufficient CPU/memory for Windows 98 + VNC
- [ ] **Headless environment**: Missing graphics libraries or drivers

## Suspected Primary Root Causes

1. **QEMU VNC Authentication Mismatch**: QEMU VNC server expects no password, but tools are trying with passwords
2. **Windows 98 Boot Incomplete**: 90 seconds is insufficient for full Windows 98 GUI startup
3. **VNC Display Configuration**: QEMU not properly directing Windows 98 output to VNC display
4. **Tool Compatibility**: VNC capture tools incompatible with QEMU's VNC implementation

## Resolution Strategy

1. Fix QEMU VNC configuration for proper password-less access
2. Extend Windows 98 boot time and add proper boot completion detection
3. Add robust VNC server readiness detection before attempting screenshots
4. Implement multiple VNC capture methods with proper error handling
5. Add Windows 98 GUI readiness validation before interaction testing
6. Ensure proper display resolution configuration in both QEMU and Windows 98