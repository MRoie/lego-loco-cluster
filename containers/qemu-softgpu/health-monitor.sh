#!/usr/bin/env bash
# QEMU Health Monitoring Script
# Provides detailed health metrics for audio, video, and system performance

set -euo pipefail

# Configuration
HEALTH_PORT=${HEALTH_PORT:-8080}
HEALTH_LOG="/tmp/health.log"
VNC_DISPLAY=${VNC_DISPLAY:-:${DISPLAY_NUM:-1}}
AUDIO_DEVICE=${AUDIO_DEVICE:-pulse}

# Logging function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$HEALTH_LOG"
}

# Get QEMU process health
get_qemu_health() {
    local qemu_pid=$(pgrep -f qemu-system-i386 || echo "")
    if [ -z "$qemu_pid" ]; then
        echo "false"
        return
    fi
    
    # Check if process is responding
    if kill -0 "$qemu_pid" 2>/dev/null; then
        echo "true"
    else
        echo "false"
    fi
}

# Get video subsystem health
get_video_health() {
    local video_health="{}"
    
    # Check VNC connectivity
    local vnc_port=5901
    if netstat -ln | grep -q ":${vnc_port}" 2>/dev/null; then
        local vnc_available="true"
        
        # Try to get VNC statistics via vncpasswd or direct connection test
        local frame_rate=0
        local display_active="false"
        
        # Check if X display is active
        if xdpyinfo -display "$VNC_DISPLAY" >/dev/null 2>&1; then
            display_active="true"
            # Estimate frame rate by checking X server activity
            local x_activity=$(xwininfo -display "$VNC_DISPLAY" -root -stats 2>/dev/null | grep -c "window" || echo "0")
            if [ "$x_activity" -gt 0 ]; then
                frame_rate=15  # Conservative estimate when X is active
            fi
        fi
        
        video_health=$(cat <<EOF
{
    "vnc_available": $vnc_available,
    "display_active": $display_active,
    "estimated_frame_rate": $frame_rate,
    "vnc_port": $vnc_port,
    "display": "$VNC_DISPLAY"
}
EOF
)
    else
        video_health='{"vnc_available": false, "display_active": false, "estimated_frame_rate": 0}'
    fi
    
    echo "$video_health"
}

# Get audio subsystem health
get_audio_health() {
    local audio_health="{}"
    
    # Check PulseAudio status
    local pulse_running="false"
    local audio_devices=0
    local audio_level=0
    
    if pgrep pulseaudio >/dev/null 2>&1; then
        pulse_running="true"
        
        # Get audio device count
        audio_devices=$(pactl list short sinks 2>/dev/null | wc -l || echo "0")
        
        # Try to get audio level (simplified)
        if command -v pactl >/dev/null 2>&1; then
            # Get default sink volume
            local sink_info=$(pactl list sinks 2>/dev/null | grep -A 15 "State: RUNNING" | head -20 || echo "")
            if echo "$sink_info" | grep -q "Volume:"; then
                audio_level=0.5  # Default moderate level when audio is working
            fi
        fi
    fi
    
    # Check ALSA devices as fallback
    local alsa_devices=0
    if command -v aplay >/dev/null 2>&1; then
        alsa_devices=$(aplay -l 2>/dev/null | grep -c "card " 2>/dev/null | head -1)
        # Handle case where grep -c returns nothing
        if [ -z "$alsa_devices" ]; then
            alsa_devices=0
        fi
    fi
    
    audio_health=$(cat <<EOF
{
    "pulse_running": $pulse_running,
    "audio_devices": $audio_devices,
    "alsa_devices": $alsa_devices,
    "estimated_level": $audio_level,
    "audio_backend": "$AUDIO_DEVICE"
}
EOF
)
    
    echo "$audio_health"
}

# Get system performance metrics
get_system_performance() {
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1 || echo "0")
    local memory_usage=$(free | grep Mem | awk '{printf "%.1f", $3/$2 * 100.0}' || echo "0")
    local load_average=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | tr -d ',' || echo "0")
    
    # Check for QEMU specific performance
    local qemu_pid=$(pgrep -f qemu-system-i386 || echo "")
    local qemu_cpu="0"
    local qemu_memory="0"
    
    if [ -n "$qemu_pid" ]; then
        qemu_cpu=$(ps -p "$qemu_pid" -o %cpu --no-headers 2>/dev/null | tr -d ' ' || echo "0")
        qemu_memory=$(ps -p "$qemu_pid" -o %mem --no-headers 2>/dev/null | tr -d ' ' || echo "0")
    fi
    
    local performance=$(cat <<EOF
{
    "cpu_usage": $cpu_usage,
    "memory_usage": $memory_usage,
    "load_average": $load_average,
    "qemu_cpu": $qemu_cpu,
    "qemu_memory": $qemu_memory,
    "qemu_pid": "$qemu_pid"
}
EOF
)
    
    echo "$performance"
}

# Get network performance
get_network_health() {
    local network_health="{}"
    
    # Check bridge and TAP interfaces
    local bridge_status="false"
    local tap_status="false"
    
    if ip link show loco-br >/dev/null 2>&1; then
        bridge_status="true"
    fi
    
    if ip link show tap0 >/dev/null 2>&1; then
        tap_status="true"
    fi
    
    # Get basic network statistics
    local tx_packets=$(cat /sys/class/net/tap0/statistics/tx_packets 2>/dev/null || echo "0")
    local rx_packets=$(cat /sys/class/net/tap0/statistics/rx_packets 2>/dev/null || echo "0")
    local tx_errors=$(cat /sys/class/net/tap0/statistics/tx_errors 2>/dev/null || echo "0")
    local rx_errors=$(cat /sys/class/net/tap0/statistics/rx_errors 2>/dev/null || echo "0")
    
    network_health=$(cat <<EOF
{
    "bridge_up": $bridge_status,
    "tap_up": $tap_status,
    "tx_packets": $tx_packets,
    "rx_packets": $rx_packets,
    "tx_errors": $tx_errors,
    "rx_errors": $rx_errors
}
EOF
)
    
    echo "$network_health"
}

# Generate complete health report
generate_health_report() {
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local qemu_healthy=$(get_qemu_health)
    local video_health=$(get_video_health)
    local audio_health=$(get_audio_health)
    local performance=$(get_system_performance)
    local network_health=$(get_network_health)
    
    # Overall health determination
    local overall_status="healthy"
    if [ "$qemu_healthy" = "false" ]; then
        overall_status="unhealthy"
    elif ! echo "$video_health" | grep -q '"vnc_available": true'; then
        overall_status="degraded"
    elif ! echo "$audio_health" | grep -q '"pulse_running": true'; then
        overall_status="degraded"
    fi
    
    cat <<EOF
{
    "timestamp": "$timestamp",
    "overall_status": "$overall_status",
    "qemu_healthy": $qemu_healthy,
    "video": $video_health,
    "audio": $audio_health,
    "performance": $performance,
    "network": $network_health
}
EOF
}

# HTTP server function
serve_health_endpoint() {
    log "Starting health monitoring HTTP server on port $HEALTH_PORT"
    
    while true; do
        {
            local health_report=$(generate_health_report)
            
            # Simple HTTP response
            echo "HTTP/1.1 200 OK"
            echo "Content-Type: application/json"
            echo "Access-Control-Allow-Origin: *"
            echo "Content-Length: ${#health_report}"
            echo ""
            echo "$health_report"
        } | nc -l -p "$HEALTH_PORT" -w 1 >/dev/null 2>&1 || true
        
        sleep 1
    done
}

# Main execution
case "${1:-serve}" in
    "serve")
        serve_health_endpoint
        ;;
    "report")
        generate_health_report
        ;;
    "test")
        echo "Testing health monitoring components..."
        echo "QEMU Health: $(get_qemu_health)"
        echo "Video Health: $(get_video_health)"
        echo "Audio Health: $(get_audio_health)"
        echo "Performance: $(get_system_performance)"
        echo "Network Health: $(get_network_health)"
        ;;
    *)
        echo "Usage: $0 [serve|report|test]"
        exit 1
        ;;
esac