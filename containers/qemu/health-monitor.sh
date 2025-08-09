#!/usr/bin/env bash
# QEMU Health Monitoring Script - Optimized for Fast Kubernetes Health Checks
# Provides essential health metrics with caching for performance

set -euo pipefail

# Configuration
HEALTH_PORT=${HEALTH_PORT:-8080}
HEALTH_LOG="/tmp/health.log"
VNC_DISPLAY=${VNC_DISPLAY:-:1}
AUDIO_DEVICE=${AUDIO_DEVICE:-pulse}
CACHE_FILE="/tmp/health_cache.json"
CACHE_TTL=${CACHE_TTL:-10}  # Cache for 10 seconds

# Fast logging function
log() {
    echo "[$(date +'%H:%M:%S')] $1" >> "$HEALTH_LOG"
}

# Check if cache is valid
is_cache_valid() {
    if [ ! -f "$CACHE_FILE" ]; then
        return 1
    fi
    
    local cache_time=$(stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0)
    local current_time=$(date +%s)
    local age=$((current_time - cache_time))
    
    [ $age -lt $CACHE_TTL ]
}

# Fast QEMU health check
get_qemu_health() {
    pgrep qemu-system-i386 >/dev/null 2>&1 && echo "true" || echo "false"
}

# Fast VNC connectivity check
get_vnc_health() {
    if netstat -ln 2>/dev/null | grep -q ":5901" || ss -ln 2>/dev/null | grep -q ":5901"; then
        echo '{"vnc_available": true, "vnc_port": 5901}'
    else
        echo '{"vnc_available": false, "vnc_port": 5901}'
    fi
}

# Fast audio health check
get_audio_health() {
    if pgrep pulseaudio >/dev/null 2>&1; then
        echo '{"pulse_running": true}'
    else
        echo '{"pulse_running": false}'
    fi
}

# Fast network health check
get_network_health() {
    local bridge_up="false"
    local tap_up="false"
    
    ip link show loco-br >/dev/null 2>&1 && bridge_up="true"
    ip link show tap0 >/dev/null 2>&1 && tap_up="true"
    
    echo "{\"bridge_up\": $bridge_up, \"tap_up\": $tap_up}"
}

# Generate lightweight health report
generate_health_report() {
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local qemu_healthy=$(get_qemu_health)
    local vnc_health=$(get_vnc_health)
    local audio_health=$(get_audio_health)
    local network_health=$(get_network_health)
    
    # Simple overall health determination
    local overall_status="healthy"
    if [ "$qemu_healthy" = "false" ]; then
        overall_status="unhealthy"
    elif ! echo "$vnc_health" | grep -q '"vnc_available": true'; then
        overall_status="degraded"
    fi
    
    cat <<EOF
{
    "timestamp": "$timestamp",
    "overall_status": "$overall_status",
    "qemu_healthy": $qemu_healthy,
    "vnc": $vnc_health,
    "audio": $audio_health,
    "network": $network_health
}
EOF
}

# Get cached or fresh health report
get_health_with_cache() {
    if is_cache_valid; then
        cat "$CACHE_FILE"
    else
        local report=$(generate_health_report)
        echo "$report" > "$CACHE_FILE"
        echo "$report"
    fi
}

# Simple health check for Kubernetes probes
simple_health_check() {
    local qemu_healthy=$(get_qemu_health)
    if [ "$qemu_healthy" = "true" ]; then
        echo "OK"
        return 0
    else
        echo "UNHEALTHY"
        return 1
    fi
}

# HTTP server function with caching
serve_health_endpoint() {
    log "Starting optimized health monitoring HTTP server on port $HEALTH_PORT"
    
    while true; do
        {
            local health_report=$(get_health_with_cache)
            
            echo "HTTP/1.1 200 OK"
            echo "Content-Type: application/json"
            echo "Access-Control-Allow-Origin: *"
            echo "Cache-Control: max-age=$CACHE_TTL"
            echo "Content-Length: ${#health_report}"
            echo ""
            echo "$health_report"
        } | nc -l -p "$HEALTH_PORT" -w 1 >/dev/null 2>&1 || true
        
        sleep 0.5  # Reduced sleep for faster response
    done
}

# Main execution
case "${1:-serve}" in
    "serve")
        serve_health_endpoint
        ;;
    "check")
        simple_health_check
        ;;
    "report")
        get_health_with_cache
        ;;
    "fresh")
        generate_health_report
        ;;
    *)
        echo "Usage: $0 [serve|check|report|fresh]"
        echo "  serve - Start HTTP health server (default)"
        echo "  check - Simple health check for K8s probes (exit 0/1)"
        echo "  report - Get cached health report"
        echo "  fresh - Generate fresh health report"
        exit 1
        ;;
esac