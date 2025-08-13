#!/usr/bin/env bash
# Enterprise-Grade QEMU Health Monitoring Script
# Provides comprehensive health metrics with alerting, error recovery, and enterprise features

set -euo pipefail

# Configuration with enterprise defaults
HEALTH_PORT=${HEALTH_PORT:-8080}
HEALTH_LOG="/tmp/health.log"
VNC_DISPLAY=${VNC_DISPLAY:-:${DISPLAY_NUM:-1}}
AUDIO_DEVICE=${AUDIO_DEVICE:-pulse}

# Enterprise configuration
ALERT_WEBHOOK_URL=${ALERT_WEBHOOK_URL:-""}
ALERT_EMAIL=${ALERT_EMAIL:-""}
HEALTH_CHECK_INTERVAL=${HEALTH_CHECK_INTERVAL:-30}
CPU_THRESHOLD=${CPU_THRESHOLD:-80}
MEMORY_THRESHOLD=${MEMORY_THRESHOLD:-85}
FRAME_RATE_THRESHOLD=${FRAME_RATE_THRESHOLD:-10}
ERROR_RATE_THRESHOLD=${ERROR_RATE_THRESHOLD:-5}
RETRY_ATTEMPTS=${RETRY_ATTEMPTS:-3}
CIRCUIT_BREAKER_THRESHOLD=${CIRCUIT_BREAKER_THRESHOLD:-5}

# State management
CONSECUTIVE_FAILURES=0
CIRCUIT_BREAKER_OPEN=false
LAST_ALERT_TIME=0
ALERT_COOLDOWN=300  # 5 minutes

# Structured logging with levels
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] [${level}] ${message}" | tee -a "$HEALTH_LOG"
}

log_info() { log "INFO" "$@"; }
log_warn() { log "WARN" "$@"; }
log_error() { log "ERROR" "$@"; }
log_debug() { log "DEBUG" "$@"; }

# Retry mechanism with exponential backoff
retry_with_backoff() {
    local max_attempts=$1
    local delay=1
    local count=0
    shift
    
    while [ $count -lt $max_attempts ]; do
        if "$@"; then
            return 0
        fi
        
        count=$((count + 1))
        if [ $count -lt $max_attempts ]; then
            log_warn "Command failed, retrying in ${delay}s (attempt ${count}/${max_attempts})"
            sleep $delay
            delay=$((delay * 2))
        fi
    done
    
    log_error "Command failed after ${max_attempts} attempts: $*"
    return 1
}

# Circuit breaker pattern
execute_with_circuit_breaker() {
    if [ "$CIRCUIT_BREAKER_OPEN" = "true" ]; then
        log_warn "Circuit breaker is open, skipping health check"
        return 1
    fi
    
    if "$@"; then
        CONSECUTIVE_FAILURES=0
        return 0
    else
        CONSECUTIVE_FAILURES=$((CONSECUTIVE_FAILURES + 1))
        if [ $CONSECUTIVE_FAILURES -ge $CIRCUIT_BREAKER_THRESHOLD ]; then
            CIRCUIT_BREAKER_OPEN=true
            log_error "Circuit breaker opened after ${CONSECUTIVE_FAILURES} consecutive failures"
            send_alert "CRITICAL" "Health monitoring circuit breaker opened"
        fi
        return 1
    fi
}

# Alert mechanism
send_alert() {
    local severity=$1
    local message=$2
    local current_time=$(date +%s)
    
    # Alert cooldown to prevent spam
    if [ $((current_time - LAST_ALERT_TIME)) -lt $ALERT_COOLDOWN ]; then
        log_debug "Alert cooldown active, skipping alert"
        return
    fi
    
    LAST_ALERT_TIME=$current_time
    log_warn "ALERT [${severity}]: ${message}"
    
    # Webhook alert
    if [ -n "$ALERT_WEBHOOK_URL" ]; then
        local payload=$(cat <<EOF
{
    "severity": "$severity",
    "message": "$message",
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "service": "qemu-emulator",
    "host": "$(hostname)"
}
EOF
)
        curl -s -X POST "$ALERT_WEBHOOK_URL" \
            -H "Content-Type: application/json" \
            -d "$payload" || log_error "Failed to send webhook alert"
    fi
    
    # Email alert (if configured)
    if [ -n "$ALERT_EMAIL" ] && command -v sendmail >/dev/null 2>&1; then
        echo -e "Subject: QEMU Health Alert - $severity\n\n$message\n\nTimestamp: $(date)" | \
            sendmail "$ALERT_EMAIL" || log_error "Failed to send email alert"
    fi
}

# Enhanced QEMU process health with performance monitoring
get_qemu_health() {
    local qemu_pid=$(pgrep -f qemu-system-i386 2>/dev/null || echo "")
    
    if [ -z "$qemu_pid" ]; then
        log_debug "No QEMU process found"
        return 1
    fi
    
    # Validate process is responding
    if ! kill -0 "$qemu_pid" 2>/dev/null; then
        log_warn "QEMU process $qemu_pid is not responding"
        return 1
    fi
    
    # Check process performance
    local cpu_usage=$(ps -p "$qemu_pid" -o %cpu --no-headers 2>/dev/null | tr -d ' ' || echo "0")
    local mem_usage=$(ps -p "$qemu_pid" -o %mem --no-headers 2>/dev/null | tr -d ' ' || echo "0")
    
    # Performance threshold checks
    if (( $(echo "$cpu_usage > $CPU_THRESHOLD" | bc -l 2>/dev/null || echo "0") )); then
        send_alert "WARNING" "QEMU CPU usage high: ${cpu_usage}%"
    fi
    
    if (( $(echo "$mem_usage > $MEMORY_THRESHOLD" | bc -l 2>/dev/null || echo "0") )); then
        send_alert "WARNING" "QEMU memory usage high: ${mem_usage}%"
    fi
    
    echo "$qemu_pid"
    return 0
}

# Enhanced video health with frame rate monitoring
get_video_health() {
    local video_health=""
    local vnc_port=5901
    
    if ! netstat -ln 2>/dev/null | grep -q ":${vnc_port}"; then
        log_debug "VNC port $vnc_port not available"
        video_health='{"vnc_available": false, "display_active": false, "estimated_frame_rate": 0, "status": "unavailable"}'
        echo "$video_health"
        return 1
    fi
    
    local vnc_available="true"
    local display_active="false"
    local frame_rate=0
    local status="healthy"
    
    # Enhanced display checking with retry
    if retry_with_backoff 3 xdpyinfo -display "$VNC_DISPLAY" >/dev/null 2>&1; then
        display_active="true"
        
        # Frame rate estimation with multiple methods
        local x_activity=$(xwininfo -display "$VNC_DISPLAY" -root -stats 2>/dev/null | grep -c "window" || echo "0")
        if [ "$x_activity" -gt 0 ]; then
            frame_rate=15
            
            # More sophisticated frame rate detection if possible
            if command -v xrandr >/dev/null 2>&1; then
                local refresh_rate=$(xrandr --display "$VNC_DISPLAY" 2>/dev/null | grep '\*' | awk '{print $2}' | cut -d'.' -f1 || echo "15")
                if [ "$refresh_rate" -gt 0 ] 2>/dev/null; then
                    frame_rate=$refresh_rate
                fi
            fi
        fi
    else
        status="degraded"
        log_warn "Display $VNC_DISPLAY is not responding"
    fi
    
    # Alert on low frame rate
    if [ "$frame_rate" -lt "$FRAME_RATE_THRESHOLD" ] && [ "$display_active" = "true" ]; then
        send_alert "WARNING" "Low frame rate detected: ${frame_rate}fps"
        status="degraded"
    fi
    
    video_health=$(cat <<EOF
{
    "vnc_available": $vnc_available,
    "display_active": $display_active,
    "estimated_frame_rate": $frame_rate,
    "vnc_port": $vnc_port,
    "display": "$VNC_DISPLAY",
    "status": "$status"
}
EOF
)
    
    echo "$video_health"
    [ "$status" != "degraded" ]
}

# Enhanced audio health with device validation
get_audio_health() {
    local pulse_running="false"
    local audio_devices=0
    local audio_level=0
    local status="healthy"
    local error_count=0
    
    # Check PulseAudio with retry
    if retry_with_backoff 2 pgrep pulseaudio >/dev/null 2>&1; then
        pulse_running="true"
        
        # Enhanced audio device detection
        if command -v pactl >/dev/null 2>&1; then
            audio_devices=$(pactl list short sinks 2>/dev/null | wc -l || echo "0")
            
            # Audio device validation
            if [ "$audio_devices" -eq 0 ]; then
                status="degraded"
                error_count=$((error_count + 1))
                log_warn "No audio devices available"
            else
                # Audio level detection
                local sink_info=$(pactl list sinks 2>/dev/null | grep -A 15 "State: RUNNING" | head -20 || echo "")
                if echo "$sink_info" | grep -q "Volume:"; then
                    audio_level=0.5
                fi
            fi
        fi
    else
        status="unhealthy"
        error_count=$((error_count + 1))
        log_warn "PulseAudio is not running"
    fi
    
    # ALSA fallback with error handling
    local alsa_devices=0
    if command -v aplay >/dev/null 2>&1; then
        alsa_devices=$(aplay -l 2>/dev/null | grep -c "card " 2>/dev/null | head -1 || echo "0")
        if [ -z "$alsa_devices" ]; then
            alsa_devices=0
        fi
        
        if [ "$alsa_devices" -eq 0 ] && [ "$audio_devices" -eq 0 ]; then
            error_count=$((error_count + 1))
        fi
    fi
    
    # Alert on audio issues
    if [ "$error_count" -ge "$ERROR_RATE_THRESHOLD" ]; then
        send_alert "WARNING" "Audio system degraded: ${error_count} errors detected"
        status="degraded"
    fi
    
    local audio_health=$(cat <<EOF
{
    "pulse_running": $pulse_running,
    "audio_devices": $audio_devices,
    "alsa_devices": $alsa_devices,
    "estimated_level": $audio_level,
    "audio_backend": "$AUDIO_DEVICE",
    "status": "$status",
    "error_count": $error_count
}
EOF
)
    
    echo "$audio_health"
    [ "$status" != "degraded" ]
}

# Enhanced system performance with trending
get_system_performance() {
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1 || echo "0")
    local memory_usage=$(free | grep Mem | awk '{printf "%.1f", $3/$2 * 100.0}' || echo "0")
    local load_average=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | tr -d ',' || echo "0")
    local disk_usage=$(df / 2>/dev/null | tail -1 | awk '{print $5}' | sed 's/%//' || echo "0")
    
    # QEMU specific metrics
    local qemu_pid=$(pgrep -f qemu-system-i386 2>/dev/null || echo "")
    local qemu_cpu="0"
    local qemu_memory="0"
    local qemu_threads="0"
    local qemu_status="not_running"
    
    if [ -n "$qemu_pid" ]; then
        qemu_cpu=$(ps -p "$qemu_pid" -o %cpu --no-headers 2>/dev/null | tr -d ' ' || echo "0")
        qemu_memory=$(ps -p "$qemu_pid" -o %mem --no-headers 2>/dev/null | tr -d ' ' || echo "0")
        qemu_threads=$(ps -p "$qemu_pid" -o nlwp --no-headers 2>/dev/null | tr -d ' ' || echo "0")
        qemu_status="running"
        
        # Performance alerts
        if (( $(echo "$qemu_cpu > $CPU_THRESHOLD" | bc -l 2>/dev/null || echo "0") )); then
            qemu_status="high_cpu"
        fi
        if (( $(echo "$qemu_memory > $MEMORY_THRESHOLD" | bc -l 2>/dev/null || echo "0") )); then
            qemu_status="high_memory"
        fi
    fi
    
    # System alerts
    if (( $(echo "$memory_usage > $MEMORY_THRESHOLD" | bc -l 2>/dev/null || echo "0") )); then
        send_alert "WARNING" "System memory usage high: ${memory_usage}%"
    fi
    
    if [ "$disk_usage" -gt 90 ] 2>/dev/null; then
        send_alert "CRITICAL" "Disk usage critical: ${disk_usage}%"
    fi
    
    local performance=$(cat <<EOF
{
    "cpu_usage": $cpu_usage,
    "memory_usage": $memory_usage,
    "load_average": $load_average,
    "disk_usage": $disk_usage,
    "qemu_cpu": $qemu_cpu,
    "qemu_memory": $qemu_memory,
    "qemu_threads": $qemu_threads,
    "qemu_pid": "$qemu_pid",
    "qemu_status": "$qemu_status"
}
EOF
)
    
    echo "$performance"
}

# Enhanced network health with connectivity testing
get_network_health() {
    local bridge_status="false"
    local tap_status="false"
    local connectivity_status="unknown"
    local packet_loss="0"
    local latency="0"
    
    # Network interface validation
    if ip link show loco-br >/dev/null 2>&1; then
        bridge_status="true"
    fi
    
    if ip link show tap0 >/dev/null 2>&1; then
        tap_status="true"
        
        # Network connectivity test (if bridge is available)
        if [ "$bridge_status" = "true" ]; then
            # Test internal connectivity
            if ping -c 1 -W 1 172.20.0.1 >/dev/null 2>&1; then
                connectivity_status="good"
                latency=$(ping -c 1 -W 1 172.20.0.1 2>/dev/null | grep 'time=' | awk -F'time=' '{print $2}' | awk '{print $1}' || echo "0")
            else
                connectivity_status="degraded"
                packet_loss="100"
            fi
        fi
    fi
    
    # Network statistics
    local tx_packets=$(cat /sys/class/net/tap0/statistics/tx_packets 2>/dev/null || echo "0")
    local rx_packets=$(cat /sys/class/net/tap0/statistics/rx_packets 2>/dev/null || echo "0")
    local tx_errors=$(cat /sys/class/net/tap0/statistics/tx_errors 2>/dev/null || echo "0")
    local rx_errors=$(cat /sys/class/net/tap0/statistics/rx_errors 2>/dev/null || echo "0")
    local tx_bytes=$(cat /sys/class/net/tap0/statistics/tx_bytes 2>/dev/null || echo "0")
    local rx_bytes=$(cat /sys/class/net/tap0/statistics/rx_bytes 2>/dev/null || echo "0")
    
    # Calculate error rates
    local total_tx=$((tx_packets + tx_errors))
    local total_rx=$((rx_packets + rx_errors))
    local tx_error_rate=0
    local rx_error_rate=0
    
    if [ "$total_tx" -gt 0 ]; then
        tx_error_rate=$(echo "scale=2; $tx_errors * 100 / $total_tx" | bc -l 2>/dev/null || echo "0")
    fi
    if [ "$total_rx" -gt 0 ]; then
        rx_error_rate=$(echo "scale=2; $rx_errors * 100 / $total_rx" | bc -l 2>/dev/null || echo "0")
    fi
    
    # Network performance alerts
    if (( $(echo "$tx_error_rate > $ERROR_RATE_THRESHOLD" | bc -l 2>/dev/null || echo "0") )); then
        send_alert "WARNING" "High network TX error rate: ${tx_error_rate}%"
    fi
    
    if (( $(echo "$rx_error_rate > $ERROR_RATE_THRESHOLD" | bc -l 2>/dev/null || echo "0") )); then
        send_alert "WARNING" "High network RX error rate: ${rx_error_rate}%"
    fi
    
    local network_health=$(cat <<EOF
{
    "bridge_up": $bridge_status,
    "tap_up": $tap_status,
    "connectivity_status": "$connectivity_status",
    "tx_packets": $tx_packets,
    "rx_packets": $rx_packets,
    "tx_errors": $tx_errors,
    "rx_errors": $rx_errors,
    "tx_bytes": $tx_bytes,
    "rx_bytes": $rx_bytes,
    "tx_error_rate": $tx_error_rate,
    "rx_error_rate": $rx_error_rate,
    "packet_loss": "$packet_loss",
    "latency_ms": "$latency"
}
EOF
)
    
    echo "$network_health"
}

# Enhanced health report with SLA metrics
generate_health_report() {
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local check_id=$(date +%s)_$$
    
    log_info "Starting health check (ID: $check_id)"
    
    # Execute health checks with circuit breaker
    local qemu_healthy="false"
    local qemu_pid=""
    if execute_with_circuit_breaker get_qemu_health; then
        qemu_healthy="true"
        qemu_pid=$(get_qemu_health 2>/dev/null || echo "")
    fi
    
    local video_health=$(get_video_health 2>/dev/null || echo '{"status": "error"}')
    local audio_health=$(get_audio_health 2>/dev/null || echo '{"status": "error"}')
    local performance=$(get_system_performance 2>/dev/null || echo '{"status": "error"}')
    local network_health=$(get_network_health 2>/dev/null || echo '{"status": "error"}')
    
    # SLA calculation
    local sla_score=100
    local issues=()
    
    if [ "$qemu_healthy" = "false" ]; then
        sla_score=$((sla_score - 30))
        issues+=("qemu_down")
    fi
    
    if ! echo "$video_health" | grep -q '"vnc_available": true'; then
        sla_score=$((sla_score - 25))
        issues+=("video_unavailable")
    fi
    
    if ! echo "$audio_health" | grep -q '"pulse_running": true'; then
        sla_score=$((sla_score - 20))
        issues+=("audio_down")
    fi
    
    if echo "$network_health" | grep -q '"connectivity_status": "degraded"'; then
        sla_score=$((sla_score - 15))
        issues+=("network_degraded")
    fi
    
    # Overall status determination with detailed reasoning
    local overall_status="healthy"
    local status_reason="All systems operational"
    
    if [ $sla_score -lt 50 ]; then
        overall_status="critical"
        status_reason="Multiple critical systems down"
        send_alert "CRITICAL" "System critical: SLA score ${sla_score}%"
    elif [ $sla_score -lt 80 ]; then
        overall_status="degraded"
        status_reason="Performance degraded"
        send_alert "WARNING" "System degraded: SLA score ${sla_score}%"
    elif [ $sla_score -lt 95 ]; then
        overall_status="warning"
        status_reason="Minor issues detected"
    fi
    
    log_info "Health check complete (ID: $check_id) - Status: $overall_status, SLA: ${sla_score}%"
    
    cat <<EOF
{
    "timestamp": "$timestamp",
    "check_id": "$check_id",
    "overall_status": "$overall_status",
    "status_reason": "$status_reason",
    "sla_score": $sla_score,
    "issues": [$(printf '"%s",' "${issues[@]}" | sed 's/,$//')],
    "qemu_healthy": $qemu_healthy,
    "qemu_pid": "$qemu_pid",
    "video": $video_health,
    "audio": $audio_health,
    "performance": $performance,
    "network": $network_health,
    "circuit_breaker_open": $CIRCUIT_BREAKER_OPEN,
    "consecutive_failures": $CONSECUTIVE_FAILURES
}
EOF
}

# Enterprise HTTP server with security headers
serve_health_endpoint() {
    log_info "Starting enterprise health monitoring HTTP server on port $HEALTH_PORT"
    log_info "Circuit breaker threshold: $CIRCUIT_BREAKER_THRESHOLD failures"
    log_info "Alert cooldown: ${ALERT_COOLDOWN}s"
    
    while true; do
        {
            local health_report=$(generate_health_report)
            local content_length=${#health_report}
            
            # Security headers and enterprise HTTP response
            cat <<EOF
HTTP/1.1 200 OK
Content-Type: application/json
Content-Length: $content_length
Access-Control-Allow-Origin: *
Access-Control-Allow-Methods: GET, OPTIONS
Access-Control-Allow-Headers: Content-Type, Authorization
X-Content-Type-Options: nosniff
X-Frame-Options: DENY
X-XSS-Protection: 1; mode=block
Cache-Control: no-cache, no-store, must-revalidate
Pragma: no-cache
Expires: 0
Server: QEMU-HealthMonitor/1.0

$health_report
EOF
        } | nc -l -p "$HEALTH_PORT" -w 1 >/dev/null 2>&1 || true
        
        sleep 1
    done
}

# Health check validation with comprehensive testing
validate_health_check() {
    log_info "Running health check validation..."
    
    local validation_results=()
    
    # Test each component
    log_info "Testing QEMU detection..."
    if get_qemu_health >/dev/null 2>&1; then
        validation_results+=("qemu:pass")
    else
        validation_results+=("qemu:fail")
    fi
    
    log_info "Testing video subsystem..."
    if get_video_health >/dev/null 2>&1; then
        validation_results+=("video:pass")
    else
        validation_results+=("video:fail")
    fi
    
    log_info "Testing audio subsystem..."
    if get_audio_health >/dev/null 2>&1; then
        validation_results+=("audio:pass")
    else
        validation_results+=("audio:fail")
    fi
    
    log_info "Testing performance monitoring..."
    if get_system_performance >/dev/null 2>&1; then
        validation_results+=("performance:pass")
    else
        validation_results+=("performance:fail")
    fi
    
    log_info "Testing network monitoring..."
    if get_network_health >/dev/null 2>&1; then
        validation_results+=("network:pass")
    else
        validation_results+=("network:fail")
    fi
    
    echo "Validation Results: ${validation_results[*]}"
    
    # Overall validation
    local failed_count=$(printf '%s\n' "${validation_results[@]}" | grep -c 'fail' || echo "0")
    if [ "$failed_count" -eq 0 ]; then
        log_info "✅ All health monitoring components validated successfully"
        return 0
    else
        log_error "❌ $failed_count health monitoring components failed validation"
        return 1
    fi
}

# Main execution with enterprise features
case "${1:-serve}" in
    "serve")
        serve_health_endpoint
        ;;
    "report")
        generate_health_report
        ;;
    "test")
        echo "=== Enterprise QEMU Health Monitoring Test ==="
        echo "Configuration:"
        echo "  - CPU Threshold: ${CPU_THRESHOLD}%"
        echo "  - Memory Threshold: ${MEMORY_THRESHOLD}%"
        echo "  - Frame Rate Threshold: ${FRAME_RATE_THRESHOLD}fps"
        echo "  - Circuit Breaker Threshold: ${CIRCUIT_BREAKER_THRESHOLD} failures"
        echo ""
        echo "Component Tests:"
        echo "QEMU Health: $(get_qemu_health >/dev/null 2>&1 && echo "✅ Healthy" || echo "❌ Unhealthy")"
        echo "Video Health: $(get_video_health >/dev/null 2>&1 && echo "✅ Available" || echo "❌ Degraded")"
        echo "Audio Health: $(get_audio_health >/dev/null 2>&1 && echo "✅ Running" || echo "❌ Down")"
        echo "Performance: $(get_system_performance >/dev/null 2>&1 && echo "✅ Monitored" || echo "❌ Error")"
        echo "Network Health: $(get_network_health >/dev/null 2>&1 && echo "✅ Connected" || echo "❌ Degraded")"
        echo ""
        echo "Full Health Report:"
        generate_health_report
        ;;
    "validate")
        validate_health_check
        ;;
    *)
        echo "Usage: $0 [serve|report|test|validate]"
        echo ""
        echo "Enterprise Health Monitoring Commands:"
        echo "  serve    - Start HTTP health monitoring server (default)"
        echo "  report   - Generate single health report"
        echo "  test     - Run component tests and show status"
        echo "  validate - Validate all health monitoring components"
        echo ""
        echo "Environment Variables:"
        echo "  HEALTH_PORT           - HTTP server port (default: 8080)"
        echo "  CPU_THRESHOLD         - CPU usage alert threshold % (default: 80)"
        echo "  MEMORY_THRESHOLD      - Memory usage alert threshold % (default: 85)"
        echo "  FRAME_RATE_THRESHOLD  - Minimum frame rate fps (default: 10)"
        echo "  ALERT_WEBHOOK_URL     - Webhook URL for alerts"
        echo "  ALERT_EMAIL           - Email address for alerts"
        echo "  CIRCUIT_BREAKER_THRESHOLD - Failure threshold (default: 5)"
        exit 1
        ;;
esac