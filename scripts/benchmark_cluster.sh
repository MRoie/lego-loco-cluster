#!/usr/bin/env bash
# Benchmark cluster VR streaming across multiple emulator counts

set -euo pipefail

CONFIG="config/instances-docker-compose.json"
LOG_ROOT=${LOG_DIR:-benchmark_logs}
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BASE_DIR="$LOG_ROOT/cluster_$TIMESTAMP"
DURATION=${DURATION:-10}
COUNTS=(1 3 9)

mkdir -p "$BASE_DIR"

log() {
    echo "[$(date '+%H:%M:%S')] $*" | tee -a "$BASE_DIR/benchmark.log"
}

ensure_docker() {
    if ! docker info >/dev/null 2>&1; then
        log "Docker is not running or not accessible"
        exit 1
    fi
}

get_urls() {
    local count=$1
    jq -r ".[0:${count}] | .[].localStreamUrl" "$CONFIG"
}

wait_stream() {
    local url=$1
    local retries=30
    for ((i=0; i<retries; i++)); do
        if curl -fsS "$url" -o /dev/null 2>/dev/null; then
            return 0
        fi
        sleep 1
    done
    return 1
}

start_env() {
    local count=$1
    case $count in
        1)
            log "Starting minimal environment (1 emulator)"
            docker-compose -f compose/docker-compose.minimal.yml up -d >/dev/null
            ;;
        3)
            log "Starting dev environment (3 emulators)"
            ./docker-compose.sh up dev --no-cleanup --no-build >/dev/null
            ;;
        9)
            log "Starting dev environment (9 emulators)"
            ./docker-compose.sh up dev --full --no-cleanup --no-build >/dev/null
            ;;
        *)
            log "Unsupported count: $count"
            exit 1
            ;;
    esac
}

stop_env() {
    log "Stopping environment"
    ./docker-compose.sh down >/dev/null || true
    docker-compose -f compose/docker-compose.minimal.yml down >/dev/null || true
}

measure() {
    local urls=($@)
    local total=0
    local results=""
    for url in "${urls[@]}"; do
        local fname=$(echo "$url" | sed 's#http://##;s#/##g').log
        if wait_stream "$url"; then
            ./scripts/benchmark_vr.sh "$url" "$DURATION" >"$BASE_DIR/$fname" 2>&1 || true
            local fps=$(grep -m1 'Average FPS' "$BASE_DIR/$fname" | awk '{print $3}')
            results+="$url $fps\n"
            total=$(echo "$total + ${fps:-0}" | bc)
        else
            echo "Failed to reach $url" >"$BASE_DIR/$fname"
            results+="$url 0\n"
        fi
    done
    local count=${#urls[@]}
    local avg="0"
    if [[ $count -gt 0 ]]; then
        avg=$(echo "scale=2; $total / $count" | bc)
    fi
    echo -e "$results" >"$BASE_DIR/results_${count}.txt"
    echo "$avg" >"$BASE_DIR/avg_${count}.txt"
    log "Average FPS for $count containers: $avg"
}

main() {
    ensure_docker
    for c in "${COUNTS[@]}"; do
        stop_env
        start_env "$c"
        urls=( $(get_urls "$c") )
        measure "${urls[@]}"
    done
    stop_env
    log "Benchmark complete. Logs stored in $BASE_DIR"
}

main "$@"
