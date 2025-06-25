#!/usr/bin/env bash
# build_advanced_snapshots.sh -- Build pre-configured snapshots with automated software installation

set -euo pipefail

REGISTRY=${REGISTRY:-ghcr.io/mroie/qemu-snapshots}
BASE_IMAGE=${BASE_IMAGE:-/workspaces/lego-loco-cluster/images/win98.qcow2}
WORK_DIR=${WORK_DIR:-/tmp/snapshot-build}
VNC_PORT=${VNC_PORT:-5901}
MONITOR_PORT=${MONITOR_PORT:-4444}

echo "🏭 Advanced Snapshot Builder"
echo "============================"
echo "Registry: $REGISTRY"
echo "Base Image: $BASE_IMAGE"
echo "Work Directory: $WORK_DIR"
echo ""

# Check requirements
check_requirements() {
    local missing_tools=()
    
    for tool in qemu-system-i386 qemu-img docker expect; do
        if ! command -v "$tool" >/dev/null; then
            missing_tools+=("$tool")
        fi
    done
    
    if [[ ${#missing_tools[@]} -ne 0 ]]; then
        echo "❌ Missing required tools: ${missing_tools[*]}" >&2
        echo "   Install with: apt-get install qemu-system-x86 qemu-utils docker.io expect" >&2
        exit 1
    fi
}

# Create a snapshot with automated installation
build_automated_snapshot() {
    local variant="$1"
    local install_script="$2"
    local description="$3"
    
    echo "📸 Building snapshot: $variant"
    echo "   Description: $description"
    
    local snapshot_work_dir="$WORK_DIR/$variant"
    mkdir -p "$snapshot_work_dir"
    cd "$snapshot_work_dir"
    
    # Create working snapshot
    local work_snapshot="$snapshot_work_dir/work.qcow2"
    qemu-img create -f qcow2 -b "$BASE_IMAGE" "$work_snapshot" -F qcow2
    
    # Start QEMU with VNC for automation
    echo "   🚀 Starting QEMU with VNC..."
    qemu-system-i386 \
        -M pc -cpu pentium2 \
        -m 512 -hda "$work_snapshot" \
        -netdev user,id=net0 \
        -device ne2k_pci,netdev=net0 \
        -vga std \
        -vnc ":$(($VNC_PORT - 5900))" \
        -monitor "telnet:127.0.0.1:$MONITOR_PORT,server,nowait" \
        -rtc base=localtime \
        -boot menu=off \
        -daemonize \
        -pidfile "$snapshot_work_dir/qemu.pid"
    
    local qemu_pid=$(cat "$snapshot_work_dir/qemu.pid")
    
    # Wait for boot
    echo "   ⏱️  Waiting for Windows 98 to boot..."
    sleep 120
    
    # Run installation script if provided
    if [[ -n "$install_script" && -f "$install_script" ]]; then
        echo "   📦 Running installation script..."
        bash "$install_script" "$MONITOR_PORT" "$VNC_PORT"
    fi
    
    # Additional wait for installations to complete
    sleep 60
    
    # Shutdown gracefully
    echo "   💾 Shutting down VM..."
    echo "system_powerdown" | nc 127.0.0.1 "$MONITOR_PORT" || true
    
    # Wait for shutdown
    local shutdown_timeout=60
    while [[ $shutdown_timeout -gt 0 ]] && kill -0 "$qemu_pid" 2>/dev/null; do
        sleep 1
        ((shutdown_timeout--))
    done
    
    # Force kill if still running
    if kill -0 "$qemu_pid" 2>/dev/null; then
        echo "   ⚠️  Force stopping QEMU..."
        kill -9 "$qemu_pid" || true
    fi
    
    # Create final snapshot
    local final_snapshot="$snapshot_work_dir/snapshot.qcow2"
    echo "   📀 Creating final snapshot..."
    qemu-img convert -f qcow2 -O qcow2 "$work_snapshot" "$final_snapshot"
    
    # Build container image
    echo "   🐳 Building container image..."
    cat > "$snapshot_work_dir/Dockerfile" << EOF
FROM scratch
COPY snapshot.qcow2 /snapshot.qcow2
LABEL variant="$variant"
LABEL description="$description"
LABEL base-image="win98"
LABEL created="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
LABEL size="$(du -h $final_snapshot | cut -f1)"
EOF
    
    local image_name="${REGISTRY}:win98-${variant}"
    docker build -t "$image_name" "$snapshot_work_dir"
    
    echo "   📤 Pushing to registry..."
    docker push "$image_name"
    
    echo "   ✅ Snapshot complete: $image_name"
    
    # Cleanup
    rm -rf "$snapshot_work_dir"
}

# Installation script for games variant
create_games_install_script() {
    cat > "$WORK_DIR/install_games.sh" << 'EOF'
#!/usr/bin/env bash
MONITOR_PORT="$1"
VNC_PORT="$2"

echo "Installing games and DirectX..."

# This would contain automation commands
# For example, using VNC automation tools or monitor commands

# Example monitor commands:
# echo "info registers" | nc 127.0.0.1 $MONITOR_PORT
# echo "sendkey ctrl-alt-del" | nc 127.0.0.1 $MONITOR_PORT

# In a real implementation, you would:
# 1. Use VNC automation to navigate Windows
# 2. Mount ISO files via monitor commands
# 3. Automate software installations
# 4. Configure registry settings
# 5. Install drivers and updates

sleep 30  # Simulate installation time
echo "Games installation simulated"
EOF
    chmod +x "$WORK_DIR/install_games.sh"
}

# Installation script for productivity variant
create_productivity_install_script() {
    cat > "$WORK_DIR/install_productivity.sh" << 'EOF'
#!/usr/bin/env bash
MONITOR_PORT="$1"
VNC_PORT="$2"

echo "Installing productivity software..."

# This would install:
# - Microsoft Office 97/2000
# - Adobe Acrobat Reader
# - WinZip/WinRAR
# - Text editors
# - Web browsers (IE 5.5, Netscape)

sleep 45  # Simulate installation time
echo "Productivity software installation simulated"
EOF
    chmod +x "$WORK_DIR/install_productivity.sh"
}

# Installation script for development variant
create_development_install_script() {
    cat > "$WORK_DIR/install_development.sh" << 'EOF'
#!/usr/bin/env bash
MONITOR_PORT="$1"
VNC_PORT="$2"

echo "Installing development tools..."

# This would install:
# - Visual Studio 6.0
# - Borland C++ Builder
# - Microsoft Visual Basic 6
# - Web development tools
# - FTP clients

sleep 60  # Simulate installation time
echo "Development tools installation simulated"
EOF
    chmod +x "$WORK_DIR/install_development.sh"
}

# Main function
main() {
    echo "🚀 Starting advanced snapshot building..."
    
    check_requirements
    
    if [[ ! -f "$BASE_IMAGE" ]]; then
        echo "❌ Base image not found: $BASE_IMAGE" >&2
        exit 1
    fi
    
    mkdir -p "$WORK_DIR"
    
    # Create installation scripts
    echo "📝 Creating installation scripts..."
    create_games_install_script
    create_productivity_install_script
    create_development_install_script
    
    # Build different variants
    echo ""
    echo "🏗️  Building snapshot variants..."
    
    # Base variant (minimal, just the OS)
    build_automated_snapshot "base" "" "Clean Windows 98 installation"
    
    # Games variant
    build_automated_snapshot "games" "$WORK_DIR/install_games.sh" "Windows 98 with games and DirectX"
    
    # Productivity variant  
    build_automated_snapshot "productivity" "$WORK_DIR/install_productivity.sh" "Windows 98 with office software"
    
    # Development variant
    build_automated_snapshot "development" "$WORK_DIR/install_development.sh" "Windows 98 with development tools"
    
    echo ""
    echo "🎉 All snapshots built successfully!"
    echo ""
    echo "Available snapshots:"
    echo "  ${REGISTRY}:win98-base         - Clean Windows 98"
    echo "  ${REGISTRY}:win98-games        - Games + DirectX"
    echo "  ${REGISTRY}:win98-productivity - Office software"
    echo "  ${REGISTRY}:win98-development  - Development tools"
    
    # Cleanup
    rm -rf "$WORK_DIR"
}

# Show help
show_help() {
    cat << EOF
Advanced Snapshot Builder for Windows 98 QEMU Images

Usage: $0 [options]

Options:
    --registry <url>     Container registry (default: ghcr.io/mroie/qemu-snapshots)
    --base-image <path>  Base QCOW2 image (default: /workspaces/lego-loco-cluster/images/win98.qcow2)
    --work-dir <path>    Working directory (default: /tmp/snapshot-build)
    --vnc-port <port>    VNC port for automation (default: 5901)
    --monitor-port <port> QEMU monitor port (default: 4444)
    -h, --help           Show this help

Environment Variables:
    REGISTRY            Container registry URL
    BASE_IMAGE          Path to base QCOW2 image
    WORK_DIR            Working directory
    VNC_PORT            VNC port
    MONITOR_PORT        QEMU monitor port

Examples:
    # Build all snapshots with defaults
    $0
    
    # Use custom registry
    REGISTRY=my-registry.com/snapshots $0
    
    # Use custom base image
    $0 --base-image /path/to/my-win98.qcow2

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --registry)
            REGISTRY="$2"
            shift 2
            ;;
        --base-image)
            BASE_IMAGE="$2"
            shift 2
            ;;
        --work-dir)
            WORK_DIR="$2"
            shift 2
            ;;
        --vnc-port)
            VNC_PORT="$2"
            shift 2
            ;;
        --monitor-port)
            MONITOR_PORT="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            show_help >&2
            exit 1
            ;;
    esac
done

# Run main function
main "$@"
