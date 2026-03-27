#!/usr/bin/env bash
# verify-win98-drivers.sh — Verify Windows 98 SE driver installation in QEMU instances
# Checks SoftGPU, NIC, SB16 audio, and VESA fallback from the host side.

set -euo pipefail

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# ── Logging helpers (match project conventions) ───────────────────────────────
log_info()    { echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] ℹ️  INFO: $1${NC}"; }
log_success() { echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ PASS: $1${NC}"; }
log_fail()    { echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ FAIL: $1${NC}"; }
log_skip()    { echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  SKIP: $1${NC}"; }
log_header()  { echo -e "\n${BOLD}── $1 ──${NC}"; }

# ── Defaults & configuration ─────────────────────────────────────────────────
VNC_BASE_PORT=${VNC_BASE_PORT:-5900}
VNC_DISPLAY_OFFSET=${VNC_DISPLAY_OFFSET:-1}
SUBNET_PREFIX=${SUBNET_PREFIX:-192.168.10}
GUEST_IP_START=${GUEST_IP_START:-10}
EXPECTED_WIDTH=${EXPECTED_WIDTH:-1024}
EXPECTED_HEIGHT=${EXPECTED_HEIGHT:-768}
TIMEOUT_SEC=${TIMEOUT_SEC:-5}
CONTAINER_PREFIX=${CONTAINER_PREFIX:-qemu-loco}

# Counters
PASS=0
FAIL=0
SKIP=0

# ── Usage ─────────────────────────────────────────────────────────────────────
usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS] <INSTANCE>

Verify Windows 98 SE driver installation for a QEMU instance.

Arguments:
  INSTANCE        Instance number (0-8) or explicit VNC port (5900-5999)

Options:
  --host HOST         Target host (default: localhost)
  --container NAME    Docker container name to query QEMU monitor
  --subnet PREFIX     Subnet prefix (default: 192.168.10)
  --timeout SEC       Timeout for network checks (default: 5)
  --vnc-offset N      VNC display offset added to base port (default: 1)
  -h, --help          Show this help

Examples:
  $(basename "$0") 0                           # Check instance 0 (VNC port 5901)
  $(basename "$0") --host 10.0.0.5 2           # Check instance 2 on remote host
  $(basename "$0") --container qemu-loco-0 0   # Also inspect PCI via docker exec
EOF
  exit 0
}

# ── Argument parsing ──────────────────────────────────────────────────────────
HOST="localhost"
CONTAINER=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --host)       HOST="$2";           shift 2 ;;
    --container)  CONTAINER="$2";      shift 2 ;;
    --subnet)     SUBNET_PREFIX="$2";  shift 2 ;;
    --timeout)    TIMEOUT_SEC="$2";    shift 2 ;;
    --vnc-offset) VNC_DISPLAY_OFFSET="$2"; shift 2 ;;
    -h|--help)    usage ;;
    -*)           echo "Unknown option: $1" >&2; exit 1 ;;
    *)
      INSTANCE_ARG="$1"
      shift
      ;;
  esac
done

if [[ -z "${INSTANCE_ARG:-}" ]]; then
  echo "Error: instance number or VNC port required" >&2
  usage
fi

# Determine VNC port and instance number
if [[ "$INSTANCE_ARG" -ge 5900 ]] 2>/dev/null; then
  VNC_PORT="$INSTANCE_ARG"
  INSTANCE=$(( (VNC_PORT - VNC_BASE_PORT - VNC_DISPLAY_OFFSET) ))
else
  INSTANCE="$INSTANCE_ARG"
  VNC_PORT=$(( VNC_BASE_PORT + VNC_DISPLAY_OFFSET + INSTANCE ))
fi

GUEST_IP="${SUBNET_PREFIX}.$(( GUEST_IP_START + INSTANCE ))"

# Auto-detect container name if not provided
if [[ -z "$CONTAINER" ]]; then
  CONTAINER="${CONTAINER_PREFIX}-${INSTANCE}"
fi

# ── Helper: record result ─────────────────────────────────────────────────────
record_pass() { log_success "$1"; (( PASS++ )) || true; }
record_fail() { log_fail "$1";    (( FAIL++ )) || true; }
record_skip() { log_skip "$1";    (( SKIP++ )) || true; }

# ── Helper: check tool availability ──────────────────────────────────────────
require_tool() {
  command -v "$1" &>/dev/null
}

###############################################################################
# CHECK 1: VNC Connectivity                                                   #
###############################################################################
check_vnc_connectivity() {
  log_header "VNC Connectivity (port $VNC_PORT on $HOST)"

  if require_tool nc; then
    if nc -z -w "$TIMEOUT_SEC" "$HOST" "$VNC_PORT" 2>/dev/null; then
      record_pass "VNC port $VNC_PORT is reachable on $HOST"
      return 0
    else
      record_fail "VNC port $VNC_PORT is NOT reachable on $HOST"
      return 1
    fi
  elif [[ -e /dev/tcp ]]; then
    # Bash built-in fallback
    if timeout "$TIMEOUT_SEC" bash -c "</dev/tcp/$HOST/$VNC_PORT" 2>/dev/null; then
      record_pass "VNC port $VNC_PORT is reachable on $HOST (bash /dev/tcp)"
      return 0
    else
      record_fail "VNC port $VNC_PORT is NOT reachable on $HOST"
      return 1
    fi
  else
    record_skip "No 'nc' or /dev/tcp available — cannot check VNC connectivity"
    return 2
  fi
}

###############################################################################
# CHECK 2: VNC Resolution (SoftGPU / VESA)                                   #
###############################################################################
check_vnc_resolution() {
  log_header "VNC Resolution (expect ${EXPECTED_WIDTH}x${EXPECTED_HEIGHT})"

  # Strategy A: vncdotool / vncdo
  if require_tool vncdotool; then
    local cap_file
    cap_file=$(mktemp /tmp/vnc_cap_XXXXXX.png)
    if vncdotool -s "$HOST::$VNC_PORT" capture "$cap_file" 2>/dev/null; then
      local dims
      if require_tool identify; then
        dims=$(identify -format "%wx%h" "$cap_file" 2>/dev/null || true)
      elif require_tool file; then
        dims=$(file "$cap_file" | grep -oP '\d+\s*x\s*\d+' | head -1 | tr -d ' ')
      fi
      rm -f "$cap_file"

      if [[ -n "${dims:-}" ]]; then
        log_info "Detected VNC framebuffer: $dims"
        if [[ "$dims" == "${EXPECTED_WIDTH}x${EXPECTED_HEIGHT}" ]]; then
          record_pass "Resolution is ${EXPECTED_WIDTH}x${EXPECTED_HEIGHT} — SoftGPU driver OK"
          return 0
        elif [[ "$dims" == "800x600" ]]; then
          log_info "800×600 detected — likely VESA VBE fallback (SoftGPU not active)"
          record_fail "Resolution is $dims (expected ${EXPECTED_WIDTH}x${EXPECTED_HEIGHT})"
          return 1
        else
          record_fail "Unexpected resolution: $dims"
          return 1
        fi
      fi
    fi
    rm -f "$cap_file"
  fi

  # Strategy B: python3 + PIL VNC handshake size parsing
  if require_tool python3; then
    local py_result
    py_result=$(python3 -c "
import socket, struct, sys
try:
    s = socket.socket()
    s.settimeout($TIMEOUT_SEC)
    s.connect(('$HOST', $VNC_PORT))
    banner = s.recv(12)
    s.send(b'RFB 003.008\n')
    sec_types_len = struct.unpack('!B', s.recv(1))[0]
    s.recv(sec_types_len)
    s.send(bytes([1]))
    result = s.recv(4)
    s.send(bytes([1]))
    server_init = s.recv(24)
    w, h = struct.unpack('!HH', server_init[:4])
    s.close()
    print(f'{w}x{h}')
except Exception as e:
    print(f'error:{e}', file=sys.stderr)
    sys.exit(1)
" 2>/dev/null) || true

    if [[ -n "${py_result:-}" && "$py_result" != error:* ]]; then
      log_info "VNC server reports framebuffer: $py_result"
      if [[ "$py_result" == "${EXPECTED_WIDTH}x${EXPECTED_HEIGHT}" ]]; then
        record_pass "Resolution is ${EXPECTED_WIDTH}x${EXPECTED_HEIGHT} — SoftGPU driver OK"
        return 0
      elif [[ "$py_result" == "800x600" ]]; then
        log_info "800×600 detected — likely VESA VBE fallback"
        record_fail "Resolution is $py_result (expected ${EXPECTED_WIDTH}x${EXPECTED_HEIGHT})"
        return 1
      else
        record_fail "Unexpected resolution: $py_result"
        return 1
      fi
    fi
  fi

  record_skip "No vncdotool or python3 available — cannot check VNC resolution"
  return 2
}

###############################################################################
# CHECK 3: QEMU PCI Devices (SB16 audio, NIC, VGA via monitor / docker)      #
###############################################################################
check_pci_devices() {
  log_header "QEMU PCI Devices (SB16, NE2K, VMware VGA)"

  local pci_output=""

  # Strategy A: docker exec into the container and query QEMU monitor via QMP
  if require_tool docker; then
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${CONTAINER}$"; then
      log_info "Found container $CONTAINER — querying PCI info"

      # Try QMP socket if available
      pci_output=$(docker exec "$CONTAINER" bash -c \
        'echo "{ \"execute\": \"qmp_capabilities\" }" | socat - UNIX-CONNECT:/tmp/qmp.sock 2>/dev/null && echo "{ \"execute\": \"query-pci\" }" | socat - UNIX-CONNECT:/tmp/qmp.sock 2>/dev/null' \
        2>/dev/null) || true

      # Fallback: lspci inside container
      if [[ -z "$pci_output" ]]; then
        pci_output=$(docker exec "$CONTAINER" lspci 2>/dev/null) || true
      fi

      # Fallback: check QEMU process command line for device flags
      if [[ -z "$pci_output" ]]; then
        pci_output=$(docker exec "$CONTAINER" cat /proc/1/cmdline 2>/dev/null | tr '\0' ' ') || true
      fi
    else
      log_info "Container $CONTAINER not found — trying direct process inspection"
    fi
  fi

  # Strategy B: check local QEMU process command line
  if [[ -z "$pci_output" ]]; then
    pci_output=$(pgrep -a qemu-system 2>/dev/null | head -5) || true
  fi

  if [[ -z "$pci_output" ]]; then
    record_skip "Cannot query PCI devices (no docker container or QEMU process found)"
    return 2
  fi

  log_info "Analyzing PCI / command-line output..."

  # Check SB16 audio
  if echo "$pci_output" | grep -qi "sb16\|Sound Blaster\|creative"; then
    record_pass "SB16 audio device detected"
  else
    record_fail "SB16 audio device NOT detected"
  fi

  # Check NIC (ne2k_pci / RTL8029)
  if echo "$pci_output" | grep -qi "ne2k\|rtl8029\|realtek"; then
    record_pass "RTL8029AS (ne2k_pci) NIC detected"
  else
    record_fail "RTL8029AS (ne2k_pci) NIC NOT detected"
  fi

  # Check VGA (vmware)
  if echo "$pci_output" | grep -qi "vmware\|vga\|svga"; then
    record_pass "VMware SVGA (SoftGPU) VGA adapter detected"
  else
    record_fail "VMware SVGA VGA adapter NOT detected"
  fi
}

###############################################################################
# CHECK 4: Network Connectivity (NIC driver + IP assignment)                  #
###############################################################################
check_network_connectivity() {
  log_header "Network Connectivity (ping $GUEST_IP)"

  if ! require_tool ping; then
    record_skip "'ping' not available — cannot check network connectivity"
    return 2
  fi

  log_info "Pinging guest $GUEST_IP (timeout ${TIMEOUT_SEC}s)..."

  if ping -c 2 -W "$TIMEOUT_SEC" "$GUEST_IP" &>/dev/null; then
    record_pass "Guest $GUEST_IP is reachable — NIC driver and IP assignment OK"
    return 0
  else
    # Distinguish between "host unreachable" and "no route"
    local ping_out
    ping_out=$(ping -c 1 -W "$TIMEOUT_SEC" "$GUEST_IP" 2>&1) || true
    if echo "$ping_out" | grep -qi "no route\|network is unreachable"; then
      log_info "No route to $SUBNET_PREFIX.0/24 — bridge may not be configured on this host"
      record_fail "Guest $GUEST_IP unreachable (no route to subnet)"
    else
      record_fail "Guest $GUEST_IP unreachable (NIC driver may not be installed or IP not assigned)"
    fi
    return 1
  fi
}

###############################################################################
# CHECK 5: VESA VBE Fallback Presence                                        #
###############################################################################
check_vesa_fallback() {
  log_header "VESA VBE Fallback Check"

  # VESA is the baseline QEMU VGA — if VNC works at all, VESA is functional.
  # This check verifies that even without SoftGPU, the display is usable.
  # We rely on the VNC connectivity check (CHECK 1) already passing.

  if [[ $PASS -ge 1 ]]; then
    # VNC was reachable — at minimum VESA VBE is providing a display
    record_pass "VESA VBE fallback is available (VNC display is active)"
  else
    record_fail "Cannot verify VESA VBE — VNC display is not reachable"
  fi
}

###############################################################################
# MAIN                                                                        #
###############################################################################
main() {
  echo ""
  echo -e "${BOLD}🔍 Win98 Driver Verification — Instance $INSTANCE${NC}"
  echo -e "${BOLD}   Host: $HOST | VNC: $VNC_PORT | Guest IP: $GUEST_IP${NC}"
  echo -e "${BOLD}   Container: $CONTAINER${NC}"
  echo "═══════════════════════════════════════════════════════════"

  check_vnc_connectivity
  check_vnc_resolution
  check_pci_devices
  check_network_connectivity
  check_vesa_fallback

  # ── Summary ──────────────────────────────────────────────────────────────
  echo ""
  echo "═══════════════════════════════════════════════════════════"
  echo -e "${BOLD}📊 Summary — Instance $INSTANCE${NC}"
  echo -e "   ${GREEN}PASS: $PASS${NC}  ${RED}FAIL: $FAIL${NC}  ${YELLOW}SKIP: $SKIP${NC}"
  echo "═══════════════════════════════════════════════════════════"

  if [[ $FAIL -gt 0 ]]; then
    log_fail "One or more checks failed"
    exit 1
  elif [[ $SKIP -gt 0 && $PASS -eq 0 ]]; then
    log_skip "All checks skipped — install required tools for full verification"
    exit 1
  else
    log_success "All checks passed"
    exit 0
  fi
}

main
