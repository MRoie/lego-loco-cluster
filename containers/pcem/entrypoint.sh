#!/usr/bin/env bash
# Boot PCem headless and publish it to the cluster as plain VNC on :5901.
#
#   Xvfb :99  →  PCem SDL window  →  x11vnc :5901  →  backend WS bridge  →  frontend
#
# The gotcha numbers referenced below are from standalone/README.md, which is
# the bring-up log this container is the product of.
set -euo pipefail

: "${DISPLAY:=:99}"
: "${SCREEN_WIDTH:=1024}"
: "${SCREEN_HEIGHT:=768}"
: "${SCREEN_DEPTH:=24}"
: "${VNC_PORT:=5901}"
: "${VNC_PASSWORD:=}"
: "${VNC_BACKEND:=xvnc}"   # xvnc (TigerVNC, RFB-native) | x11vnc (Xvfb + screen grabber)
: "${XVNC_FRAMERATE:=60}"  # Xvnc -FrameRate cap; 60 is TigerVNC's own default.
                           # Nine Xvnc at 60 cost ~0.4-0.5 core fleet-wide in
                           # update-compare work on an already-contended node;
                           # the chart drops this to 30 (see values-pcem.yaml).
: "${HEALTH_PORT:=8080}"

# Guest audio: a private PulseAudio daemon with a null sink for PCem's OpenAL
# output, plus a raw-PCM TCP tap the backend bridges to the browser. See
# start_audio() for why this exists at all (OpenAL falls back to the *host*
# sound card without it).
: "${AUDIO_ENABLE:=1}"
: "${AUDIO_PORT:=5902}"
: "${AUDIO_RATE:=48000}"   # matches PCem's FREQ (48 kHz stereo S16)

: "${PCEM_HOME:=/pcem}"
: "${DISK_DIR:=/images}"
: "${DISK_NAME:=win98-loco.vhd}"
: "${CDROM_PATH:=}"
: "${PCEM_CONFIG:=}"           # optional: path to a hand-written pcem.cfg
: "${PCEM_VNC_MOUSE:=1}"       # remote-pointer patch, see patches/vnc-mouse.py
# absolute = the guest cursor goes exactly where the client points (what VNC,
# RDP and tablets/touch actually send). relative = nudge by the client's
# motion, which drifts as soon as the guest applies pointer acceleration.
: "${PCEM_POINTER_MODE:=absolute}"
# Guest pointer ballistics, used to predict where a mouse packet lands.
#
# MEASURED, correcting an earlier account that was wrong throughout: the
# emulator samples the host pointer at 49.9 Hz (pollmouse_delay=2 gating a
# 100 Hz loop), and that clock — not the mouse device — sets pixels per second.
# PCem does not emulate 1200 baud at all; the UART drains 333 packets/s against
# an offered 50, so nothing is ever lost to a full FIFO.
#
# PCEM_MOUSE_CREEP is the largest packet the guest moves 1:1 and
# PCEM_MOUSE_DOUBLE_MIN the smallest it is known to double; packets between
# them are never emitted, so the uncertain band costs nothing.
#
# Note this model is open loop against a curve that CHANGES: LEGO LOCO calls
# SystemParametersInfo(SPI_SETMOUSE) at startup and installs its own, which is
# why in-game travel differs and why writing Control Panel\Mouse never helped.
# LOCO has no DirectInput import — it drives the Windows system cursor.
: "${PCEM_MOUSE_CREEP:=2}"
: "${PCEM_MOUSE_DOUBLE_MIN:=8}"
: "${PCEM_MOUSE_SPEED:=1}"
# Per-packet limit of the emulated device: 255 for PS/2, 127 for serial.
: "${PCEM_MOUSE_DEVICE_MAX:=255}"
: "${PCEM_MOUSE_MAX_PACKET:=120}"
: "${PCEM_NETCARD:=none}"      # none | ne2000 | rtl8029as
# Guest LAN. LEGO LOCO multiplayer is DirectPlay over TCP/IP, which needs the
# two guests on one layer-2 segment — SLiRP (PCem's default) is host-NAT and
# cannot do that, so this uses the PCap backend enabled by patches/linux-pcap.py.
#   none   — no guest networking
#   direct — bridge straight onto an existing container interface (works when
#            the container runtime gives every container a real L2 bridge,
#            e.g. a user-defined Docker network)
#   vxlan  — build a local bridge + tap and mesh it to peer pods over VXLAN,
#            the same mechanism containers/qemu-softgpu uses. Required on
#            Kubernetes, where pods are joined at L3 and foreign MACs do not
#            cross the CNI.
: "${PCEM_NET_MODE:=none}"
: "${PCEM_NET_IFACE:=eth0}"    # direct mode: interface to bridge onto
: "${PCEM_BRIDGE:=loco-br}"
: "${PCEM_TAP:=tap0}"          # only used when PCEM_NET_DEV_MODE=tap
# veth, not tap: a tap has no carrier unless something holds its /dev/net/tun
# fd, and PCem's pcap backend never opens it. See setup_guest_lan().
: "${PCEM_NET_DEV_MODE:=veth}" # veth | tap
: "${PCEM_VETH:=loco0}"        # PCem's pcap device
: "${PCEM_VETH_PEER:=loco0br}" # the end enslaved to the bridge
: "${VXLAN_ID:=42}"
: "${VXLAN_PORT:=4789}"
: "${PCEM_MAC:=}"              # defaults to 52:54:00:lo:co:<instance ordinal>
# Ordinal 0 hands out guest addresses so a single golden disk can be cloned to
# N instances: the lease follows the MAC, so each guest gets a stable, distinct
# IP with nothing configured inside Windows.
: "${GUEST_DHCP:=1}"
# Every instance boots a clone of one golden disk, so without this they all
# share a NetBIOS name and Windows refuses to start Microsoft Networking with
# "Error 38: The computer name you specified is already in use".
: "${GUEST_IDENTITY:=1}"
# Windows desktop resolution, as the Win9x registry spells it ("640,480").
# Empty leaves whatever the image was installed with. Applied by the same
# StartUp .REG import as the computer name, so it takes effect on the boot
# *after* the one that writes it.
: "${GUEST_RESOLUTION:=}"
: "${GUEST_COLOUR_DEPTH:=16}"
# Switch off Windows' pointer acceleration so a mickey is a pixel. Keep this
# and PCEM_MOUSE_SPEED in agreement. Like the computer name, it is imported at
# logon, so it governs from the *next* boot onwards.
: "${GUEST_MOUSE_ACCEL:=0}"
: "${GUEST_MOUSE_THRESHOLD:=500}"
# Launch LEGO LOCO from WIN.INI's [windows] run= at logon. Driving the desktop
# icon over VNC is not reliable, so the launch is moved off the GUI. Short 8.3
# path because run= takes bare program paths with no quoting.
: "${GUEST_AUTOSTART_LOCO:=1}"
: "${GUEST_LOCO_PATH:=C:\PROGRA~1\LEGOME~1\CONSTR~1\LEGOLO~1\EXE\LOCO.EXE}"
# Type the instance name into LEGO LOCO's red main-menu ticket once the menu
# appears. The in-game name is game state, not registry state, so the .REG
# mechanism above cannot reach it — scripts/loco-autoname.py drives the GUI
# over RFB instead (see start_autoname()).
: "${GUEST_AUTONAME:=1}"
# Desktop launchers for the LOCO postbag/savegame dirs — the sync/share
# surface for the upcoming postbag-over-network feature.
: "${GUEST_SHORTCUTS:=1}"
: "${GUEST_NAME_PREFIX:=LOCO-}"
: "${GUEST_WORKGROUP:=LOCOLAND}"
# Guest addressing. Ordinal N gets ${GUEST_SUBNET}.$((GUEST_IP_BASE + N)) by
# DHCP reservation, so instance 0 is always 192.168.10.10 and instance 1 always
# .11 no matter what order they boot in.
: "${GUEST_SUBNET:=192.168.10}"
: "${GUEST_IP_BASE:=10}"
: "${GUEST_MAX_ORDINAL:=15}"   # how many reservations the DHCP server writes
: "${DHCP_SERVER_IP:=192.168.10.200}"
: "${DHCP_RANGE_START:=192.168.10.10}"
: "${DHCP_RANGE_END:=192.168.10.99}"
: "${PCEM_MEM_SIZE:=65536}"    # KB
# Windows binds chipset drivers at install time, so the board has to match the
# one the disk snapshot was installed on — booting the LEGO LOCO snapshot on
# 430vx instead lands in a PnP re-detect storm (VGA fallback, no mouse, a
# "New Hardware Found" wizard asking for the Windows 98 SE CD).
: "${PCEM_MODEL:=fic_va503p}"
: "${PCEM_GFXCARD:=v3_3000}"
# 0 = MS serial, 1 = Mouse Systems serial, 2 = PS/2 2-button, 3 = PS/2
# Intellimouse. The snapshot's Windows install has a serial mouse bound; a PS/2
# mouse leaves the guest cursor frozen with no error anywhere.
: "${PCEM_MOUSE_TYPE:=0}"
: "${PCEM_DYNAREC:=1}"
# Make the guest fill the whole VNC framebuffer.
#
# PCem sizes its SDL window to the guest's video mode, so a Windows desktop at
# 800x600 (or LOCO dropping to 640x480) sits in the corner of the 1024x768 Xvnc
# screen and the browser tile shows black bars around it — and the bars move
# every time the guest changes mode.
#
# vid_resize = 2 is PCem's "custom resolution": the window is pinned to
# custom_width/custom_height and win_doresize is ignored (wx-sdl2-display.c:645),
# so a guest mode change no longer resizes the window. sdl_renderer_present()
# always scales the guest framebuffer to the window size via
# sdl_scale(video_fullscreen_scale, ...), so the picture stretches to fill it.
#
# The [SDL2] `fullscreen` key is deliberately not used: at startup it only ticks
# the menu checkbox — the actual SDL fullscreen switch lives in the menu handler
# (wx-sdl2.c:1005) and never runs headless.
#
# Scale: 0 = FULLSCR_SCALE_FULL (stretch), 1 = 4:3, 2 = square pixels,
# 3 = integer multiples (video.h:43). 1024x768 and the guest's modes are all
# 4:3, so 0 and 1 look the same here; 0 keeps it right if either side changes.
: "${PCEM_VID_RESIZE:=2}"
: "${PCEM_FULLSCREEN_SCALE:=0}"
# Floppy types: 0=None 1=5.25" 360k 2=5.25" 1.2M 3=5.25" 1.2M dual 4=3.5" 720k
# 5=3.5" 1.44M 6=3.5" 1.44M 3-Mode 7=3.5" 2.88M. A 1.44M drive matches what
# this Award BIOS puts in CMOS by default; anything else POSTs with
# "Floppy disk(s) fail (40)" and halts on "Press F1 to continue".
: "${PCEM_FLOPPY_A_TYPE:=5}"
: "${PCEM_FLOPPY_B_TYPE:=0}"

# Disk geometry of the shipped snapshot: 1023 x 16 x 63 x 512 (~503 MB), one
# FAT16 partition starting at LBA 63. gotcha #14 — these must match the image.
: "${DISK_CYLINDERS:=1023}"
: "${DISK_HEADS:=16}"
: "${DISK_SECTORS:=63}"

: "${SNAPSHOT_IMAGE:=ghcr.io/mroie/lego-loco-cluster/emulator-snapshot:pcem-win98-loco-1024x768}"
: "${SNAPSHOT_PULL:=auto}"     # auto | always | never
: "${SNAPSHOT_CACHE_DIR:=}"    # optional node-local cache, populated on first pull

: "${BIOS_AUTOKEY:=1}"         # clear a first-boot "CMOS checksum error, press F1"
: "${INSTANCE_ID:=${POD_NAME:-pcem-0}}"

DISK_PATH="${DISK_DIR}/${DISK_NAME}"
RUN_DIR=/run/pcem
CFG_PATH="${PCEM_HOME}/pcem.cfg"

log()      { echo "[$(date -u +%H:%M:%S)] $*"; }
log_ok()   { log "✅ $*"; }
log_warn() { log "⚠️  $*"; }
log_err()  { log "❌ $*" >&2; }

mkdir -p "$RUN_DIR" "$PCEM_HOME" "$DISK_DIR"

########################################################################
# 1. Disk image
########################################################################
ensure_disk() {
  if [ "$SNAPSHOT_PULL" = "always" ] && [ -n "$SNAPSHOT_IMAGE" ]; then
    log "Re-pulling snapshot (SNAPSHOT_PULL=always)"
    rm -f "$DISK_PATH"
  fi

  if [ -f "$DISK_PATH" ]; then
    log_ok "Disk present: $DISK_PATH ($(stat -c%s "$DISK_PATH") bytes)"
    return 0
  fi

  # Each pod runs its own copy of the disk (PCem writes through to it), so a
  # node-local cache turns "N pods × 500 MB pulled from GHCR" into one pull.
  local cached="${SNAPSHOT_CACHE_DIR}/${DISK_NAME}"
  if [ -n "$SNAPSHOT_CACHE_DIR" ] && [ -f "$cached" ]; then
    log "Seeding disk from node cache ${cached}"
    cp "$cached" "${DISK_PATH}.partial" && mv "${DISK_PATH}.partial" "$DISK_PATH"
    log_ok "Disk ready from cache: $DISK_PATH ($(stat -c%s "$DISK_PATH") bytes)"
    return 0
  fi

  if [ "$SNAPSHOT_PULL" = "never" ] || [ -z "$SNAPSHOT_IMAGE" ]; then
    log_err "No disk at $DISK_PATH and snapshot pulling is disabled"
    return 1
  fi

  log "Pulling Windows 98 + LEGO LOCO disk from ${SNAPSHOT_IMAGE}"
  pull-snapshot.sh "$SNAPSHOT_IMAGE" "$DISK_PATH"
  log_ok "Disk ready: $DISK_PATH ($(stat -c%s "$DISK_PATH") bytes)"

  if [ -n "$SNAPSHOT_CACHE_DIR" ] && [ -d "$SNAPSHOT_CACHE_DIR" ] && [ -w "$SNAPSHOT_CACHE_DIR" ]; then
    log "Populating node cache ${cached}"
    cp "$DISK_PATH" "${cached}.partial" && mv "${cached}.partial" "$cached" || \
      log_warn "Could not populate node cache (continuing)"
  fi
}

# gotcha #6: hdd_file.c opens writable drives with fopen64(fn, "rb+") and
# silently falls back to IDE_NONE — a read-only mount looks exactly like a
# missing disk, with no error logged in a release build.
check_disk_writable() {
  if [ ! -w "$DISK_PATH" ]; then
    log_err "Disk $DISK_PATH is not writable — PCem will silently see no drive"
    return 1
  fi
}

########################################################################
# 2. Config
########################################################################
render_config() {
  if [ -n "$PCEM_CONFIG" ] && [ -f "$PCEM_CONFIG" ]; then
    log "Using supplied config $PCEM_CONFIG"
    cp "$PCEM_CONFIG" "$CFG_PATH"
    return 0
  fi

  # gotcha #16: cdrom_drive = 0 means "host CD-ROM device 0", not "no drive"
  # and not "use cdrom_path". 200 (CDROM_IMAGE) is the only value that reads
  # an ISO; -1 is the real "no drive".
  local cdrom_drive=-1
  if [ -n "$CDROM_PATH" ]; then
    cdrom_drive=200
  fi

  cat > "$CFG_PATH" <<EOF
model = ${PCEM_MODEL}
cpu_manufacturer = 0
cpu = 10
cpu_use_dynarec = ${PCEM_DYNAREC}
cpu_waitstates = 0
fpu = builtin
mem_size = ${PCEM_MEM_SIZE}
gfxcard = ${PCEM_GFXCARD}
video_speed = -1
voodoo = 0
sndcard = sb16
gameblaster = 0
gus = 0
ssi2001 = 0
hdd_controller = ide
# gotcha #5: hdc_* is Primary Master (ide_fn index 0), not hda_*.
hdc_fn = ${DISK_PATH}
hdc_sectors = ${DISK_SECTORS}
hdc_heads = ${DISK_HEADS}
hdc_cylinders = ${DISK_CYLINDERS}
hdd_sectors = 0
hdd_heads = 0
hdd_cylinders = 0
hdd_fn =
hde_sectors = 0
hde_heads = 0
hde_cylinders = 0
hde_fn =
hdf_sectors = 0
hdf_heads = 0
hdf_cylinders = 0
hdf_fn =
hdg_sectors = 0
hdg_heads = 0
hdg_cylinders = 0
hdg_fn =
hdh_sectors = 0
hdh_heads = 0
hdh_cylinders = 0
hdh_fn =
hdi_sectors = 0
hdi_heads = 0
hdi_cylinders = 0
hdi_fn =
netcard = ${PCEM_NETCARD}
macaddr = ${PCEM_MAC}
mouse_type = ${PCEM_MOUSE_TYPE}
joystick_type = 0
disc_a =
disc_b =
drive_a_type = ${PCEM_FLOPPY_A_TYPE}
drive_b_type = ${PCEM_FLOPPY_B_TYPE}
bpb_disable = 0
cdrom_drive = ${cdrom_drive}
cdrom_channel = 2
cdrom_path = ${CDROM_PATH}
cd_speed = 24
cd_model = pcemcd
zip_channel = -1
enable_sync = 1
lpt1_device =
vid_resize = ${PCEM_VID_RESIZE}
video_fullscreen_scale = ${PCEM_FULLSCREEN_SCALE}
video_fullscreen_first = 0

[Joysticks]
joystick_0_nr = 0
joystick_1_nr = 0

[SDL2]
screenshot_format = png
screenshot_flash = 0
custom_width = ${SCREEN_WIDTH}
custom_height = ${SCREEN_HEIGHT}
fullscreen = 0
fullscreen_mode = 0
scale = 1
scale_mode = 1
vsync = 0
focus_dim = 0
alternative_update_lock = 0
render_driver = software

[GL3]
input_scale = 1.000000
input_stretch = 0
shader_refresh_rate = 0.000000

[GL3 Shaders]
shaders = 0
EOF
  log_ok "Rendered $CFG_PATH (${PCEM_MODEL} / ${PCEM_GFXCARD} / ${PCEM_MEM_SIZE}KB)"
}

# gotcha #3: PCem's data root is $HOME/.pcem, and `ln -sfn src dst` nests
# inside dst when dst already exists as a directory — PCem creates those
# directories itself on first run, so remove before linking.
prepare_pcem_home() {
  mkdir -p "${PCEM_HOME}/.pcem"
  # Copied rather than symlinked: boards with a flash BIOS (the VA-503+ among
  # them) persist `flash.bin` next to their ROM, so the ROM directory has to be
  # writable by whoever the pod runs as.
  rm -rf "${PCEM_HOME}/.pcem/roms"
  cp -r /opt/pcem/roms "${PCEM_HOME}/.pcem/roms"

  # CMOS lives here, and it decides whether this boot is unattended.
  #
  # With no CMOS for the configured board, the Award BIOS POSTs with
  # "CMOS checksum error - Defaults loaded" and then *halts* on "Press F1 to
  # continue" — forever, on a headless pod. So: keep NVRAM on the disk volume
  # so it survives restarts, and seed a first boot from a known-good CMOS
  # captured for this board (nvr-seed/, same idea as PCem's own nvr/ defaults).
  mkdir -p "${DISK_DIR}/nvr"
  rm -rf "${PCEM_HOME}/.pcem/nvr"
  ln -sfn "${DISK_DIR}/nvr" "${PCEM_HOME}/.pcem/nvr"
  cp -n /opt/pcem/nvr-defaults/* "${DISK_DIR}/nvr/" 2>/dev/null || true

  # PCem names CMOS "<config basename>.<model>.nvr" (nvr.c nvrfopen()).
  NVR_FILE="${DISK_DIR}/nvr/$(basename "${CFG_PATH}" .cfg).${PCEM_MODEL}.nvr"
  if [ ! -f "$NVR_FILE" ] && [ -f "/opt/pcem/nvr-seed/${PCEM_MODEL}.nvr" ]; then
    cp "/opt/pcem/nvr-seed/${PCEM_MODEL}.nvr" "$NVR_FILE"
    log_ok "Seeded CMOS for ${PCEM_MODEL} — first boot will be unattended"
  fi
  if [ -f "$NVR_FILE" ]; then
    NVR_PRESENT=1
  else
    NVR_PRESENT=0
    log_warn "No CMOS for ${PCEM_MODEL}; the BIOS will stop on 'Press F1' — falling back to auto-keying"
  fi

  # PCem segfaults on startup against a fresh HOME: paths_onconfigloaded()
  # calls pclog() before anything has created $HOME/.pcem/logs, pclog's
  # fopen() therefore returns NULL, and it fputs() to it unchecked
  # (pc.c:107 — the crash is inside glibc, which makes it look like a
  # library problem rather than a missing directory). Non-release builds
  # only; create every directory PCem expects up front.
  mkdir -p "${PCEM_HOME}/.pcem/configs" \
           "${PCEM_HOME}/.pcem/screenshots" \
           "${PCEM_HOME}/.pcem/logs"

  # That same debug-build logging is extremely chatty and never rotates, so
  # by default send it to /dev/null rather than growing without bound in a
  # pod that stays up for days. PCEM_DEBUG_LOG=1 keeps the real file.
  if [ "${PCEM_DEBUG_LOG:-0}" = "1" ]; then
    rm -f "${PCEM_HOME}/.pcem/logs/pcem.log"
  else
    ln -sfn /dev/null "${PCEM_HOME}/.pcem/logs/pcem.log"
  fi
}

########################################################################
# 2b. Guest LAN
########################################################################
instance_ordinal() {
  # StatefulSet pods are <name>-<ordinal>; anything else is instance 0.
  case "$INSTANCE_ID" in
    *-[0-9]*) echo "${INSTANCE_ID##*-}" ;;
    *)        echo 0 ;;
  esac
}

# A guest's MAC and LAN address are both pure functions of its ordinal, so
# every pod can work out any peer's address without discovery — including its
# own, which is what gets published to the UI as the address other players type
# into LEGO LOCO's TCP/IP join box.
guest_mac_for() { printf '52:54:00:10:c0:%02x' "$1"; }
guest_ip_for()  { echo "${GUEST_SUBNET}.$((GUEST_IP_BASE + $1))"; }
# The one name this instance goes by everywhere: NetBIOS computer name, DHCP
# host name, and what loco-autoname.py types into the game's ticket.
guest_name()    { printf '%s%02d' "$GUEST_NAME_PREFIX" "$(instance_ordinal)"; }

GUEST_IP=""
PCAP_DEVICE=""

setup_guest_lan() {
  PCAP_DEVICE=""
  [ "$PCEM_NET_MODE" = "none" ] && return 0

  local ordinal
  ordinal="$(instance_ordinal)"
  [ -n "$PCEM_MAC" ] || PCEM_MAC="$(guest_mac_for "$ordinal")"
  [ -n "$GUEST_IP" ] || GUEST_IP="$(guest_ip_for "$ordinal")"

  if [ "$PCEM_NET_MODE" = "direct" ]; then
    PCAP_DEVICE="$PCEM_NET_IFACE"
    log_ok "Guest LAN: bridging directly onto ${PCAP_DEVICE} (mac ${PCEM_MAC})"
    return 0
  fi

  # vxlan: a local bridge carries the guest's link and a VXLAN port per peer pod.
  ip link add "$PCEM_BRIDGE" type bridge 2>/dev/null || true
  ip link set "$PCEM_BRIDGE" up || { log_err "cannot bring up ${PCEM_BRIDGE} — needs NET_ADMIN"; return 1; }

  # A veth pair, NOT a tap.
  #
  # This is the bug that made vxlan mode look plumbed and carry nothing. A tap
  # device only has carrier while some process holds its /dev/net/tun file
  # descriptor — that fd *is* the far end of the wire. PCem's PCap backend
  # attaches with libpcap, i.e. an AF_PACKET socket on the interface, and never
  # opens /dev/net/tun. So tap0 sat at NO-CARRIER/state DOWN, its bridge port
  # stayed `disabled`, and the kernel dropped every frame the bridge tried to
  # forward to it (visible as a rising TX-dropped with RX 0 / TX 0 forever).
  # Nothing reached the guest and nothing left it — no DHCPDISCOVER was ever
  # emitted, which is why the guests fell back to APIPA.
  #
  # `direct` mode worked precisely because it hands PCem the container's eth0,
  # which is one end of a veth pair and therefore has carrier.
  #
  # A veth pair has carrier as soon as both ends are up, with no fd to hold, so
  # libpcap on one end and the bridge on the other behave like a real cable.
  if [ "$PCEM_NET_DEV_MODE" = "tap" ]; then
    # Kept for a host that genuinely wants a tap. `ip tuntap add`, not
    # `ip link add ... type tuntap`: the latter is not valid syntax and fails
    # with "Cannot find device" on the very next command.
    ip tuntap add dev "$PCEM_TAP" mode tap 2>/dev/null || true
    ip link set "$PCEM_TAP" up || { log_err "cannot bring up ${PCEM_TAP} — is /dev/net/tun present?"; return 1; }
    ip link set "$PCEM_TAP" master "$PCEM_BRIDGE"
    PCAP_DEVICE="$PCEM_TAP"
    log_warn "PCEM_NET_DEV_MODE=tap: PCem's pcap backend does not hold the tun fd, so ${PCEM_TAP} will have no carrier"
  else
    ip link del "$PCEM_VETH" 2>/dev/null || true
    ip link add "$PCEM_VETH" type veth peer name "$PCEM_VETH_PEER" \
      || { log_err "cannot create veth pair ${PCEM_VETH}/${PCEM_VETH_PEER} — needs NET_ADMIN"; return 1; }
    ip link set "$PCEM_VETH_PEER" master "$PCEM_BRIDGE"
    ip link set "$PCEM_VETH" up
    ip link set "$PCEM_VETH_PEER" up
    PCAP_DEVICE="$PCEM_VETH"
  fi

  if [ -n "${POD_IP:-}" ]; then
    ip link add "vxlan${VXLAN_ID}" type vxlan id "$VXLAN_ID" dstport "$VXLAN_PORT" \
        local "$POD_IP" nolearning 2>/dev/null || true
    ip link set "vxlan${VXLAN_ID}" up
    ip link set "vxlan${VXLAN_ID}" master "$PCEM_BRIDGE"
    mesh_vxlan_peers &
  else
    log_warn "POD_IP unset — VXLAN mesh skipped, the guest link is local-only"
  fi

  # Turn off TX checksum offload on everything the guest's traffic crosses.
  #
  # This is the second reason DHCP never completed, and it is invisible without
  # a packet capture. A reply generated on this host — dnsmasq's DHCPOFFER —
  # leaves the stack with skb->ip_summed = CHECKSUM_PARTIAL: the UDP checksum
  # field holds only the pseudo-header partial sum, on the understanding that
  # the NIC will finish it. Since every device in the path advertises
  # tx-checksumming, the kernel never calls skb_checksum_help(), so nothing ever
  # does. A kernel peer would not care. But libpcap hands PCem the raw bytes,
  # PCem hands them to the emulated NE2000, and Windows 98 computes the checksum
  # in software, finds it wrong, and silently discards the datagram. The OFFER
  # is on the wire and correct in every other respect — broadcast MAC,
  # 255.255.255.255, broadcast flag set — and the client simply never sees it.
  #
  # The tell: the guest's own DISCOVERs arrive fine (Windows checksums them in
  # software) and it answers ARP (no checksum at all), so the path and PCem's
  # RX are provably good and only checksummed L4 dies.
  #
  # The veth's bridge-side end is the load-bearing one — it is the device the
  # frame is transmitted on before veth_xmit hands it over — but the others are
  # free.
  local dev
  for dev in "$PCEM_VETH_PEER" "$PCEM_VETH" "$PCEM_BRIDGE"; do
    [ -e "/sys/class/net/${dev}" ] || continue
    ethtool -K "$dev" tx off >/dev/null 2>&1 || \
      log_warn "could not disable TX checksum offload on ${dev} — DHCP replies may reach the guest with a bad UDP checksum"
  done

  # Carrier is the thing that was broken before, so say it out loud rather than
  # leaving it to be discovered by a silent DHCP failure ten minutes later.
  local carrier
  carrier="$(cat "/sys/class/net/${PCAP_DEVICE}/carrier" 2>/dev/null || echo '?')"
  if [ "$carrier" = "1" ]; then
    log_ok "Guest LAN: ${PCEM_BRIDGE} + ${PCAP_DEVICE} (carrier up) + vxlan${VXLAN_ID} (mac ${PCEM_MAC})"
  else
    log_warn "Guest LAN: ${PCAP_DEVICE} has NO CARRIER (carrier=${carrier}) — the bridge will drop everything toward the guest"
  fi
}

start_guest_dhcp() {
  [ "$GUEST_DHCP" = "1" ] || return 0
  [ "$PCEM_NET_MODE" = "none" ] && return 0
  [ "$(instance_ordinal)" = "0" ] || return 0

  local iface="$PCEM_BRIDGE"
  [ "$PCEM_NET_MODE" = "direct" ] && iface="$PCEM_NET_IFACE"

  # dnsmasq rather than scripts/mini-dhcp.py: the hand-rolled server's OFFERs
  # were ignored by the Windows 98 client, which then fell back to an APIPA
  # 169.254 address. Windows is fussy about the exact option set in a BOOTP
  # reply and this is not worth reverse-engineering.
  if command -v dnsmasq >/dev/null 2>&1; then
    # The server needs an address on the guest subnet to answer from.
    ip addr add "${DHCP_SERVER_IP}/24" dev "$iface" 2>/dev/null || true
    # --dhcp-broadcast is the load-bearing flag. Without it dnsmasq answers
    # unicast to the address it is about to hand out, the Windows 98 client
    # does not own that address yet so its IP stack drops the reply, and the
    # server then ARPs for a host that cannot answer:
    #
    #   192.168.10.200.67 > 192.168.10.13.68: BOOTP/DHCP, Reply
    #   ARP Request who-has 192.168.10.13 tell 192.168.10.200   (unanswered)
    #
    # The lease never completes and Windows falls back to APIPA.
    #
    # Reservations, one per ordinal, so a guest's address is a property of its
    # identity rather than of the order it happened to boot in. That is what
    # makes "instance N is at 192.168.10.(10+N)" something the UI can print and
    # a player can type into LEGO LOCO's TCP/IP box before the guest has even
    # finished booting. Without them the pool hands out addresses first-come and
    # the host's address changes across restarts.
    local -a reservations=()
    local i
    for i in $(seq 0 $((GUEST_MAX_ORDINAL))); do
      reservations+=("--dhcp-host=$(guest_mac_for "$i"),$(guest_ip_for "$i")")
    done

    dnsmasq --interface="$iface" --bind-interfaces --except-interface=lo \
            --no-daemon --no-hosts --no-resolv --port=0 \
            --dhcp-authoritative --dhcp-broadcast \
            --dhcp-range="${DHCP_RANGE_START},${DHCP_RANGE_END},255.255.255.0,12h" \
            "${reservations[@]}" \
            --dhcp-option=3 --dhcp-option=6 \
            --log-dhcp >"${RUN_DIR}/dhcp.log" 2>&1 &
    echo $! > "${RUN_DIR}/dhcp.pid"
    log_ok "Guest DHCP (dnsmasq) on ${iface}: ${DHCP_RANGE_START}-${DHCP_RANGE_END}"
  else
    python3 /usr/local/bin/mini-dhcp.py "$iface" >"${RUN_DIR}/dhcp.log" 2>&1 &
    echo $! > "${RUN_DIR}/dhcp.pid"
    log_warn "dnsmasq missing; falling back to mini-dhcp.py on ${iface}"
  fi
}

# Peers come and go as pods reschedule, so the FDB is reconciled rather than
# written once. Head-end replication: one "all-zero MAC" entry per peer makes
# the kernel flood broadcast/unknown-unicast to each of them, which is what
# DirectPlay's session discovery needs.
# Head-end replication: one all-zeros FDB entry per peer pod tells the VXLAN
# device where to send frames it has no better destination for. With
# `nolearning` and no remote/group on the device, a vxlan with no such entry has
# nowhere to send anything and vxlan_xmit() drops every frame — visible as
# tx_packets=0 with tx_dropped climbing.
#
# `set +e` and the `|| ip=""` are load-bearing, not defensive noise. This runs
# backgrounded while `set -euo pipefail` is in effect, and `getent hosts` exits
# 2 for a name that does not resolve. Under pipefail that status became the
# assignment's status, and errexit then killed the whole subshell on the first
# unresolvable peer. StatefulSet ordinal 0 starts before ordinal 1 exists, so
# that lookup was guaranteed to fail on the first pass of the first pod — the
# one pod that also runs DHCP. The mesh loop died seconds after starting and
# silently never ran again, so ordinal 0 could never reach any guest but its
# own. Nothing logged, and `ip link` showed a perfectly healthy vxlan device.
mesh_vxlan_peers() {
  local svc="${EMULATOR_SERVICE_NAME:-}" ns="${POD_NAMESPACE:-default}"
  local i peer ip
  [ -n "$svc" ] || return 0
  set +e
  local -A announced=()
  while :; do
    # Resolve every POSSIBLE ordinal, not EMULATOR_REPLICAS' worth: that env is
    # frozen at pod boot, so a pod born at replicas=4 would mesh ordinals 0-3
    # forever no matter how far the fleet scaled. Measured consequence of the
    # old loop: after a scale to 9, guests 4-6 could reach the DHCP server but
    # its replies flooded only toward the original four pods — a one-way mesh,
    # no leases, machines invisible to the LAN. Ordinals that do not exist
    # simply fail to resolve; GUEST_MAX_ORDINAL bounds the DNS chatter.
    local -A desired=()
    i=0
    while [ "$i" -le "${GUEST_MAX_ORDINAL:-15}" ]; do
      peer="${svc}-${i}.${svc}.${ns}.svc.cluster.local"
      ip="$(getent hosts "$peer" 2>/dev/null | awk '{print $1; exit}')" || ip=""
      if [ -n "$ip" ] && [ "$ip" != "${POD_IP:-}" ]; then
        desired["$ip"]="${svc}-${i}"
      fi
      i=$((i + 1))
    done

    # Add what is missing...
    local have
    for ip in "${!desired[@]}"; do
      have="$(bridge fdb show dev "vxlan${VXLAN_ID}" self 2>/dev/null | grep -c "^00:00:00:00:00:00 dst ${ip} ")"
      if [ "${have:-0}" = "0" ]; then
        if bridge fdb append 00:00:00:00:00:00 dev "vxlan${VXLAN_ID}" dst "$ip" 2>/dev/null; then
          [ "${announced[$ip]:-}" = "1" ] || log_ok "VXLAN peer ${desired[$ip]} at ${ip}"
          announced["$ip"]=1
        fi
      fi
    done

    # ...and prune what no longer belongs. A restarted peer keeps its ordinal
    # but changes pod IP; without pruning, floods keep going to the dead
    # address too, and the FDB grows a graveyard.
    while read -r line; do
      ip="$(printf '%s' "$line" | awk '{for (j=1;j<NF;j++) if ($j=="dst") print $(j+1)}')"
      [ -n "$ip" ] || continue
      if [ -z "${desired[$ip]:-}" ]; then
        bridge fdb del 00:00:00:00:00:00 dev "vxlan${VXLAN_ID}" dst "$ip" 2>/dev/null &&
          log_warn "VXLAN peer ${ip} gone — pruned from the flood list"
        unset "announced[$ip]"
      fi
    done < <(bridge fdb show dev "vxlan${VXLAN_ID}" self 2>/dev/null | grep "^00:00:00:00:00:00 dst ")

    sleep 30
  done
}


# net_type and pcap_device live in PCem's GLOBAL config ($HOME/.pcem/pcem.cfg),
# not in the machine config passed to --config. Getting this wrong is silent:
# ne2000 just falls back to SLiRP.
#
# vid_resize is read twice — from the global config in pc.c:682 and from the
# machine config in wx-sdl2.c:299 — so write it in both places rather than
# depend on which load runs last.
write_global_config() {
  local global="${PCEM_HOME}/.pcem/pcem.cfg"
  cat > "$global" <<EOF
vid_resize = ${PCEM_VID_RESIZE}
window_remember = 0
EOF
  if [ -n "$PCAP_DEVICE" ]; then
    cat >> "$global" <<EOF
net_type = 1
pcap_device = ${PCAP_DEVICE}
EOF
    log_ok "PCem global config: net_type=1 (PCap) pcap_device=${PCAP_DEVICE}"
  fi
}

# Append a line to the guest's AUTOEXEC.BAT, once. Idempotent because this runs
# on every pod start and the disk survives restarts — appending blindly would
# grow the file without bound.
append_autoexec_line() {
  local mtoolsrc="$1" line="$2"
  local tmp="${RUN_DIR}/autoexec.bat"

  MTOOLSRC="$mtoolsrc" MTOOLS_SKIP_CHECK=1 mtype c:/AUTOEXEC.BAT > "$tmp" 2>/dev/null || : > "$tmp"
  if grep -qiF "$line" "$tmp" 2>/dev/null; then
    return 0
  fi
  # CRLF, because this is read by COMMAND.COM.
  printf '%s\r\n' "$line" >> "$tmp"
  if MTOOLSRC="$mtoolsrc" MTOOLS_SKIP_CHECK=1 mcopy -o "$tmp" c:/AUTOEXEC.BAT 2>/dev/null; then
    log_ok "AUTOEXEC.BAT: added '${line}'"
  else
    log_warn "could not update AUTOEXEC.BAT"
  fi
}

# Set a key in a section of a guest .INI file.
#
# Used for WIN.INI's [windows] run=, which is how LEGO LOCO gets launched
# without anyone clicking anything. Driving the desktop icon over VNC is not
# reliable — a double-click registers as two single clicks even at an 0.08s
# hold, and click-then-Enter does not open it either — so the launch is moved
# off the GUI entirely.
#
# run= takes a space-separated list of *programs*, with no arguments. That is
# why this passes a bare short-name path: an earlier attempt at
# "run=regedit /s C:\LOCOID.REG" made Windows try to launch three separate
# things, one of which was an interactive Registry Editor that stole focus.
set_guest_ini_key() {
  local mtoolsrc="$1" inipath="$2" section="$3" key="$4" value="$5"
  local tmp="${RUN_DIR}/guest.ini"

  MTOOLSRC="$mtoolsrc" MTOOLS_SKIP_CHECK=1 mtype "$inipath" > "$tmp" 2>/dev/null || {
    log_warn "could not read ${inipath}"
    return 1
  }

  SECTION="$section" KEY="$key" VALUE="$value" python3 - "$tmp" <<'PY'
import os, sys, pathlib

path = pathlib.Path(sys.argv[1])
section, key, value = os.environ["SECTION"], os.environ["KEY"], os.environ["VALUE"]

# Keep CRLF and the original bytes: this file is decades old, is not UTF-8, and
# Windows will happily choke on a stray lone LF.
raw = path.read_bytes().decode("latin-1")
lines = raw.split("\r\n")

out, in_section, done = [], False, False
for line in lines:
    stripped = line.strip()
    if stripped.startswith("[") and stripped.endswith("]"):
        # Leaving the target section without having found the key: add it here,
        # so the key lands inside its own section rather than at end of file.
        if in_section and not done:
            out.append("%s=%s" % (key, value))
            done = True
        in_section = stripped.lower() == ("[%s]" % section).lower()
    elif in_section and not done and stripped.lower().startswith(key.lower() + "="):
        out.append("%s=%s" % (key, value))
        done = True
        continue
    out.append(line)

if not done:
    if not in_section:
        out.append("[%s]" % section)
    out.append("%s=%s" % (key, value))

path.write_bytes("\r\n".join(out).encode("latin-1"))
PY

  if MTOOLSRC="$mtoolsrc" MTOOLS_SKIP_CHECK=1 mcopy -o "$tmp" "$inipath" 2>/dev/null; then
    log_ok "$(basename "$inipath"): [${section}] ${key}=${value}"
  else
    log_warn "could not write ${inipath}"
  fi
}

# Give each instance its own computer name by writing a .REG onto the guest
# filesystem and having Windows import it at logon.
#
# The name lives in the registry (SYSTEM.DAT), which is the old Win9x CREG
# format that no Linux tool can edit offline — hivex and chntpw are both
# NT-only. So instead of editing the registry we hand Windows a .REG file and
# a WIN.INI "run=" line, which is plain text and editable with mtools.
#
# mtools reads the VHD in place given the partition offset (LBA 63 * 512) and
# MTOOLS_SKIP_CHECK=1; without that variable it refuses this disk outright
# with "Big disks not supported on this architecture".
#
# Caveat: Windows reads the computer name at boot, so an imported name takes
# effect on the *next* boot. First start of a fresh disk still collides.
inject_guest_identity() {
  [ "$GUEST_IDENTITY" = "1" ] || return 0
  command -v mcopy >/dev/null 2>&1 || { log_warn "mtools missing; skipping guest identity"; return 0; }

  local name reg mtoolsrc
  name="$(guest_name)"

  mtoolsrc="${RUN_DIR}/mtoolsrc"
  printf 'drive c: file="%s" offset=32256\n' "$DISK_PATH" > "$mtoolsrc"

  reg="${RUN_DIR}/locoid.reg"
  # CRLF: this is read by a 1998 Windows tool, not by us.
  {
    printf 'REGEDIT4\r\n\r\n'
    printf '[HKEY_LOCAL_MACHINE\\System\\CurrentControlSet\\Services\\VxD\\VNETSUP]\r\n'
    printf '"ComputerName"="%s"\r\n' "$name"
    printf '"Workgroup"="%s"\r\n' "$GUEST_WORKGROUP"
    printf '\r\n'
    # The name Windows actually registers on the network lives HERE, not under
    # VNETSUP. Both keys are live on this image; setting only VNETSUP left every
    # clone announcing the image's baked-in name, so the second guest onto the
    # LAN hit "Error 38: the computer name you specified is already in use".
    #
    # The two values above are the control that proves it: same file, same key,
    # same import — Workgroup landed (LOCOLAND registered on the wire on both
    # guests) while ComputerName did not. Workgroup has one source, so VNETSUP's
    # copy is used; ComputerName has two, and this one wins.
    #
    # It looks like an NT-only key. It is not — it is live on Windows 98 SE.
    printf '[HKEY_LOCAL_MACHINE\\System\\CurrentControlSet\\Control\\ComputerName\\ComputerName]\r\n'
    printf '"ComputerName"="%s"\r\n' "$name"
    printf '\r\n'
    # TCP/IP host name, which is what goes out as DHCP option 12. Cosmetic for
    # the game, but it is how the lease file identifies a guest, so keeping it
    # in step makes the DHCP log readable.
    printf '[HKEY_LOCAL_MACHINE\\System\\CurrentControlSet\\Services\\VxD\\MSTCP]\r\n'
    printf '"HostName"="%s"\r\n' "$name"
    printf '\r\n'
    # Desktop resolution. LEGO Loco plays in a fixed-size window, so on a
    # roomier desktop the world view is a small scrolling pane with scrollbars
    # down the side. Matching the desktop to the game's window makes the game
    # the whole screen; PCem then stretches that to the full VNC framebuffer,
    # so the browser tile is all game.
    #
    # Win9x keeps this per hardware profile under Config\<profile>, not under
    # CurrentControlSet. 0001 is the standard single-profile key.
    if [ -n "$GUEST_RESOLUTION" ]; then
      printf '[HKEY_LOCAL_MACHINE\\Config\\0001\\Display\\Settings]\r\n'
      printf '"Resolution"="%s"\r\n' "$GUEST_RESOLUTION"
      printf '"BitsPerPixel"="%s"\r\n' "$GUEST_COLOUR_DEPTH"
      printf '\r\n'
    fi
    # Pointer ballistics. The absolute-pointer patch works by predicting where
    # a mouse packet lands, and Windows' default curve doubles any packet that
    # reaches MouseThreshold1 (6) — measured, the test is >= not >. Staying
    # under that ceiling is exact but caps tracking at ~200 px/s, so switch
    # the curve off instead: a mickey is then a pixel, packets can be large,
    # and the desktop behaves the way DirectInput already does inside a game.
    # PCEM_MOUSE_SPEED must agree with this or the model mispredicts.
    if [ "$GUEST_MOUSE_ACCEL" = "0" ]; then
      printf '[HKEY_CURRENT_USER\\Control Panel\\Mouse]\r\n'
      printf '"MouseSpeed"="0"\r\n'
      # High, not zero. The ballistics double a packet that *reaches* the
      # threshold, so a threshold of 0 means every packet qualifies — setting
      # these to 0 to "turn acceleration off" asks for the opposite of what it
      # looks like. Putting them above any packet we will ever emit
      # (PCEM_MOUSE_MAX_PACKET is 120) is what actually makes a mickey a pixel.
      printf '"MouseThreshold1"="%s"\r\n' "$GUEST_MOUSE_THRESHOLD"
      printf '"MouseThreshold2"="%s"\r\n' "$GUEST_MOUSE_THRESHOLD"
      printf '\r\n'
    fi
  } > "$reg"

  MTOOLSRC="$mtoolsrc" MTOOLS_SKIP_CHECK=1 mcopy -o "$reg" c:/LOCOID.REG 2>/dev/null || {
    log_warn "could not write guest identity to the disk"
    return 0
  }

  # Import it from AUTOEXEC.BAT, in real mode, before Windows starts.
  #
  # The StartUp-folder approach this replaces could never have worked, for a
  # reason that is structural rather than a bug: Windows reads the computer name
  # when it initialises networking at boot, and the StartUp folder runs at the
  # *end* of logon. Even on a perfect run the name would only take effect on the
  # following boot — and in practice it never took effect at all, so every guest
  # kept the image's baked-in name and the second one to join the LAN put up
  # "Error 38: The computer name you specified is already in use on the network".
  #
  # REGEDIT.EXE is the same binary in real mode, where /L and /R point it at the
  # registry hives directly. At AUTOEXEC time Windows has not loaded, so the
  # hives are not in use and the merge lands before anything reads them. This is
  # the documented Win9x registry-recovery procedure, used here for its timing.
  #
  # The marker file is how we tell "the script did not run" from "the script ran
  # and the setting did not stick" — the two failures look identical from
  # outside and we have already lost an afternoon to not being able to
  # distinguish them.
  local init="${RUN_DIR}/locoinit.bat"
  {
    printf '@ECHO OFF\r\n'
    printf 'REM Written by the loco-pcem entrypoint. Do not edit by hand.\r\n'
    printf 'IF NOT EXIST C:\\LOCOID.REG GOTO END\r\n'
    printf 'IF NOT EXIST C:\\WINDOWS\\REGEDIT.EXE GOTO NOREG\r\n'
    printf 'C:\\WINDOWS\\REGEDIT.EXE /L:C:\\WINDOWS\\SYSTEM.DAT /R:C:\\WINDOWS\\USER.DAT C:\\LOCOID.REG\r\n'
    printf 'ECHO imported %s > C:\\LOCOINIT.LOG\r\n' "$name"
    printf 'GOTO END\r\n'
    printf ':NOREG\r\n'
    printf 'ECHO no-regedit > C:\\LOCOINIT.LOG\r\n'
    printf ':END\r\n'
  } > "$init"
  MTOOLSRC="$mtoolsrc" MTOOLS_SKIP_CHECK=1 mcopy -o "$init" c:/LOCOINIT.BAT 2>/dev/null || {
    log_warn "could not write C:\\LOCOINIT.BAT"
    return 0
  }
  append_autoexec_line "$mtoolsrc" 'CALL C:\LOCOINIT.BAT'

  # Keep a StartUp-folder script too, purely as an instrument. It writes a
  # *different* marker, so one boot tells us whether the StartUp folder executes
  # at all on this image — the question we could not answer while both the
  # delivery and the effect were failing silently. If AUTOEXEC does the job this
  # is redundant; if it does not, this is the fallback, one boot late.
  local stup="${RUN_DIR}/locostup.bat"
  printf '@ECHO OFF\r\nECHO startup-ran > C:\\LOCOSTUP.LOG\r\nREGEDIT /S C:\\LOCOID.REG\r\n' > "$stup"
  MTOOLSRC="$mtoolsrc" MTOOLS_SKIP_CHECK=1 \
    mcopy -o "$stup" "c:/WINDOWS/Start Menu/Programs/StartUp/LOCOID.BAT" 2>/dev/null || \
    MTOOLSRC="$mtoolsrc" MTOOLS_SKIP_CHECK=1 \
      mcopy -o "$stup" "c:/WINDOWS/STARTM~1/PROGRAMS/STARTUP/LOCOID.BAT" 2>/dev/null || \
      log_warn "could not place the StartUp probe"

  if [ "$GUEST_AUTOSTART_LOCO" = "1" ]; then
    set_guest_ini_key "$mtoolsrc" c:/WINDOWS/WIN.INI windows run "$GUEST_LOCO_PATH" || true
  fi

  if [ -n "$GUEST_RESOLUTION" ]; then
    log_ok "Guest identity: computer name ${name}, workgroup ${GUEST_WORKGROUP}, display ${GUEST_RESOLUTION}x${GUEST_COLOUR_DEPTH}bpp"
  else
    log_ok "Guest identity: computer name ${name}, workgroup ${GUEST_WORKGROUP}"
  fi
}

# Desktop launchers for LEGO LOCO's POSTBAG and SAVEGAME directories.
#
# These two dirs are the sync/share surface for the upcoming postbag-over-
# network feature: mail sent between guests lands as files in POSTBAG, and
# SAVEGAME is what a shared session resumes from. Putting them on the desktop
# gives players — and anyone debugging over VNC — a one-click Explorer view of
# what arrived, instead of a spelunk four directories deep.
#
# .BAT launchers rather than real .lnk shortcuts: a Shell Link's target is a
# LinkTargetIDList of binary shell item IDs that Explorer resolves against its
# own namespace — fiddly to forge offline and silently ignored by Win98 when
# malformed. `start <dir>` from a batch file opens the same Explorer window,
# and a batch file is plain text mtools can write. Same pre-boot mtools pass
# as inject_guest_identity, so the shortcuts appear from the next boot.
inject_desktop_shortcuts() {
  [ "$GUEST_SHORTCUTS" = "1" ] || return 0
  command -v mcopy >/dev/null 2>&1 || { log_warn "mtools missing; skipping desktop shortcuts"; return 0; }

  # Same drive mapping inject_guest_identity writes; rewritten here so this
  # function stands alone when GUEST_IDENTITY=0.
  local mtoolsrc="${RUN_DIR}/mtoolsrc"
  printf 'drive c: file="%s" offset=32256\n' "$DISK_PATH" > "$mtoolsrc"

  # 8.3 spellings throughout — mtools addresses the FAT short names, and
  # COMMAND.COM wants an unquoted path (the long one has spaces).
  local base='c:/PROGRA~1/LEGOME~1/CONSTR~1/LEGOLO~1/ART-RES'
  local dosbase='C:\PROGRA~1\LEGOME~1\CONSTR~1\LEGOLO~1\ART-RES'

  local sub bat
  for sub in POSTBAG SAVEGAME; do
    # Create the dir if the game has not yet — a launcher into a missing dir
    # opens an error box instead of a window. mmd errors when it already
    # exists, which is the common case; ignore it.
    MTOOLSRC="$mtoolsrc" MTOOLS_SKIP_CHECK=1 mmd "${base}/${sub}" 2>/dev/null || true

    bat="${RUN_DIR}/${sub}.bat"
    # CRLF: read by COMMAND.COM. On Win98, `start <dir>` opens Explorer on it.
    printf '@echo off\r\nstart %s\\%s\r\n' "$dosbase" "$sub" > "$bat"
    if MTOOLSRC="$mtoolsrc" MTOOLS_SKIP_CHECK=1 mcopy -o "$bat" "c:/WINDOWS/Desktop/${sub}.BAT" 2>/dev/null; then
      log_ok "Desktop shortcut ${sub}.BAT -> ${dosbase}\\${sub}"
    else
      log_warn "could not write desktop shortcut ${sub}.BAT"
    fi
  done
}

########################################################################
# 2c. Guest audio
#
# PCem's sound path is OpenAL, not SDL — SDL only carries video here. With no
# audio daemon in the pod, OpenAL-soft walks its backend list until something
# opens, lands on ALSA, and opens the *node's* /dev/snd: the LAN game plays
# out of the Kubernetes host's speakers. So run a private PulseAudio daemon
# whose only sink is a null sink; nothing ever reaches real hardware, and the
# null sink's .monitor is a capture tap that module-simple-protocol-tcp
# re-exposes as headerless s16le PCM on ${AUDIO_PORT} for the backend's
# WebSocket audio bridge.
########################################################################
AUDIO_READY=0

start_audio() {
  [ "$AUDIO_ENABLE" = "1" ] || { log "Guest audio disabled (AUDIO_ENABLE=${AUDIO_ENABLE})"; return 0; }
  command -v pulseaudio >/dev/null 2>&1 || { log_warn "pulseaudio not installed; continuing without guest audio"; return 0; }

  local pa="${RUN_DIR}/pulse.pa"
  cat > "$pa" <<EOF
# Native protocol on a pod-local socket — this is what PCem's OpenAL connects
# to. auth-anonymous because the pod is single-tenant and PCem has no cookie.
load-module module-native-protocol-unix socket=${RUN_DIR}/pulse.sock auth-anonymous=1
# The only sink: renders to nowhere, and its .monitor is the capture tap.
load-module module-null-sink sink_name=loco rate=${AUDIO_RATE} channels=2
set-default-sink loco
# Raw PCM out to the cluster. Fixed format so nothing downstream negotiates.
load-module module-simple-protocol-tcp source=loco.monitor record=true format=s16le rate=${AUDIO_RATE} channels=2 port=${AUDIO_PORT} listen=0.0.0.0
EOF

  # -n: do NOT load default.pa — it probes ALSA and grabs /dev/snd, the exact
  # behaviour this daemon exists to prevent. exit-idle-time=-1: no browser
  # connected between sessions must not shut the daemon down.
  pulseaudio -n --file="$pa" --daemonize=no --exit-idle-time=-1 \
      --log-target=stderr >"${RUN_DIR}/pulse.log" 2>&1 &
  echo $! > "${RUN_DIR}/pulse.pid"

  for _ in $(seq 1 25); do
    if [ -S "${RUN_DIR}/pulse.sock" ]; then
      AUDIO_READY=1
      log_ok "PulseAudio up — null sink 'loco' @ ${AUDIO_RATE}Hz, PCM tap on :${AUDIO_PORT}"
      return 0
    fi
    sleep 0.2
  done
  # Video must never depend on audio: a daemon that failed to start costs
  # sound, not the pod.
  log_warn "PulseAudio socket never appeared (see ${RUN_DIR}/pulse.log) — continuing without guest audio"
}

########################################################################
# 3. Display + VNC
#
# Two backends. `xvnc` (default) runs TigerVNC's Xvnc, which *is* an X server
# with RFB built in: PCem draws into it and clients read the same framebuffer,
# so there is no screen scraping at all. `x11vnc` is the older Xvfb + screen
# grabber arrangement, kept because it is what containers/qemu-softgpu uses.
#
# Prefer xvnc. Scraping an emulator that repaints continuously costs x11vnc
# ~95% of a core per instance, and under Kubernetes it also mis-handles the
# RFB handshake: clients get a socket that connects and then never receives
# the version banner (libvncserver's WebSocket sniff aborts instead of falling
# through to plain RFB), which shows up in the browser as a tile that is
# "connected" and permanently black.
########################################################################
start_display() {
  local dpy="${DISPLAY#:}"
  rm -f "/tmp/.X${dpy}-lock" "/tmp/.X11-unix/X${dpy}" 2>/dev/null || true

  if [ "$VNC_BACKEND" = "xvnc" ]; then
    local auth=(-SecurityTypes None)
    if [ -n "$VNC_PASSWORD" ]; then
      printf '%s\n%s\n\n' "$VNC_PASSWORD" "$VNC_PASSWORD" \
        | vncpasswd -f > "${RUN_DIR}/vncpasswd" 2>/dev/null
      auth=(-SecurityTypes VncAuth -PasswordFile "${RUN_DIR}/vncpasswd")
    fi

    Xvnc "$DISPLAY" \
        -geometry "${SCREEN_WIDTH}x${SCREEN_HEIGHT}" -depth "${SCREEN_DEPTH}" \
        -rfbport "$VNC_PORT" -interface 0.0.0.0 \
        -FrameRate "$XVNC_FRAMERATE" \
        -AlwaysShared -AcceptKeyEvents -AcceptPointerEvents -AcceptSetDesktopSize=0 \
        -desktop "loco-pcem" \
        "${auth[@]}" >"${RUN_DIR}/xvnc.log" 2>&1 &
    echo $! > "${RUN_DIR}/display.pid"
  else
    Xvfb "$DISPLAY" -screen 0 "${SCREEN_WIDTH}x${SCREEN_HEIGHT}x${SCREEN_DEPTH}" \
        -ac +extension GLX +render -noreset >"${RUN_DIR}/xvfb.log" 2>&1 &
    echo $! > "${RUN_DIR}/display.pid"
  fi

  for _ in $(seq 1 40); do
    if xdpyinfo -display "$DISPLAY" >/dev/null 2>&1; then
      log_ok "${VNC_BACKEND} X server up on $DISPLAY (${SCREEN_WIDTH}x${SCREEN_HEIGHT}x${SCREEN_DEPTH})"
      return 0
    fi
    sleep 0.5
  done
  log_err "X server did not come up; see ${RUN_DIR}/xvnc.log ${RUN_DIR}/xvfb.log"
  return 1
}

start_vnc() {
  if [ "$VNC_BACKEND" = "xvnc" ]; then
    # Xvnc serves RFB itself — nothing else to start.
    wait_for_vnc && log_ok "Xvnc serving RFB on 0.0.0.0:${VNC_PORT}"
    return 0
  fi

  local auth=(-nopw)
  if [ -n "$VNC_PASSWORD" ]; then
    x11vnc -storepasswd "$VNC_PASSWORD" "${RUN_DIR}/vncpasswd" >/dev/null 2>&1
    auth=(-rfbauth "${RUN_DIR}/vncpasswd")
  fi

  # -noxdamage: PCem repaints its whole window every emulated frame, so
  # damage-driven updates degenerate into an event storm. Fixed-rate polling
  # does bounded work per tick. -noipv6: on a pod without usable IPv6 the
  # IPv6 bind fails and x11vnc spins on the bad descriptor.
  x11vnc -display "$DISPLAY" \
         -rfbport "$VNC_PORT" -noipv6 \
         -forever -shared -noxdamage -noxfixes -repeat \
         -defer 10 -wait 10 \
         "${auth[@]}" \
         -o "${RUN_DIR}/x11vnc.log" -bg >/dev/null 2>&1

  wait_for_vnc && log_ok "x11vnc serving RFB on 0.0.0.0:${VNC_PORT}"
}

wait_for_vnc() {
  for _ in $(seq 1 40); do
    if (exec 3<>"/dev/tcp/127.0.0.1/${VNC_PORT}") 2>/dev/null; then
      exec 3>&- 2>/dev/null || true
      return 0
    fi
    sleep 0.5
  done
  log_warn "nothing is accepting on ${VNC_PORT}"
  return 1
}

########################################################################
# 4. PCem
########################################################################
start_pcem() {
  cd "$PCEM_HOME"

  # Point OpenAL at our daemon, explicitly. PCem's audio is OpenAL (not SDL),
  # and OpenAL-soft only *prefers* Pulse — if the connection races or fails it
  # silently falls through to ALSA and opens the host sound card via /dev/snd.
  # ALSOFT_DRIVERS=pulse pins the backend so the failure mode is "no sound",
  # never "sound on the node's speakers".
  if [ "$AUDIO_READY" = "1" ]; then
    export PULSE_SERVER="unix:${RUN_DIR}/pulse.sock"
    export ALSOFT_DRIVERS=pulse
  fi

  HOME="$PCEM_HOME" \
  PCEM_VNC_MOUSE="$PCEM_VNC_MOUSE" \
  PCEM_POINTER_MODE="$PCEM_POINTER_MODE" \
  PCEM_MOUSE_CREEP="$PCEM_MOUSE_CREEP" \
  PCEM_MOUSE_DOUBLE_MIN="$PCEM_MOUSE_DOUBLE_MIN" \
  PCEM_MOUSE_SPEED="$PCEM_MOUSE_SPEED" \
  PCEM_MOUSE_MAX_PACKET="$PCEM_MOUSE_MAX_PACKET" \
  PCEM_MOUSE_DEVICE_MAX="$PCEM_MOUSE_DEVICE_MAX" \
  PCEM_VNC_MOUSE_DEBUG="${PCEM_VNC_MOUSE_DEBUG:-0}" \
  SDL_VIDEODRIVER=x11 \
  LIBGL_ALWAYS_SOFTWARE=1 \
    pcem --config "$CFG_PATH" >"${RUN_DIR}/pcem.log" 2>&1 &
  PCEM_PID=$!
  echo "$PCEM_PID" > "${RUN_DIR}/pcem.pid"
  log_ok "PCem started (pid ${PCEM_PID})"
}

# Watch for LEGO LOCO's main menu and type this instance's name into its red
# ticket (scripts/loco-autoname.py). Backgrounded: the menu is minutes of
# guest boot away, and the script exits 0 on every path — a missed menu costs
# the in-game name, never the pod. ${RUN_DIR}/autoname.done marks success,
# which is how "the menu never showed" is told apart from "it typed the name"
# without watching the log scroll by.
start_autoname() {
  [ "$GUEST_AUTONAME" = "1" ] || return 0
  LOCO_GUEST_NAME="$(guest_name)" \
  AUTONAME_HOST=127.0.0.1 \
  AUTONAME_PORT="$VNC_PORT" \
  AUTONAME_MARKER="${RUN_DIR}/autoname.done" \
    python3 /usr/local/bin/loco-autoname.py >"${RUN_DIR}/autoname.log" 2>&1 &
  echo $! > "${RUN_DIR}/autoname.pid"
  log_ok "Autoname watcher started for $(guest_name) (log: ${RUN_DIR}/autoname.log)"
}

# The SDL render window ("PCem v17 - ...") is separate from the tiny wx
# top-level frame (gotcha #12). Only the former should be visible.
find_sdl_window() {
  xdotool search --name "^PCem v17" 2>/dev/null | tail -1
}

place_window() {
  local winid=""
  for _ in $(seq 1 60); do
    winid="$(find_sdl_window)"
    [ -n "$winid" ] && break
    sleep 1
  done
  if [ -z "$winid" ]; then
    log_warn "PCem SDL window never appeared — the VNC view will be blank"
    return 1
  fi

  # No window manager here, so place it ourselves and give it X input focus:
  # SDL only receives key events for the focused window.
  # windowactivate as well as windowfocus: under Xvnc, focus alone leaves the
  # SDL window without the input focus the guest needs, and keystrokes go
  # nowhere. There is no window manager here to do this for us.
  xdotool windowmove "$winid" 0 0 2>/dev/null || true
  xdotool windowraise "$winid" 2>/dev/null || true
  xdotool windowactivate "$winid" 2>/dev/null || true
  xdotool windowfocus "$winid" 2>/dev/null || true
  echo "$winid" > "${RUN_DIR}/sdl-window-id"
  log_ok "PCem SDL window $winid placed at 0,0 and focused"

  # Park the ~10x10 wx frame off in a corner so it never overlaps the guest.
  local wxid
  for wxid in $(xdotool search --name "^PCem$" 2>/dev/null); do
    [ "$wxid" = "$winid" ] && continue
    xdotool windowmove "$wxid" "$((SCREEN_WIDTH - 12))" "$((SCREEN_HEIGHT - 12))" 2>/dev/null || true
  done

  if [ "$PCEM_VNC_MOUSE" = "0" ]; then
    # Unpatched behaviour: PCem needs one real XTest click to start accepting
    # input at all (gotcha #8). x11vnc's own synthetic clicks do not do it.
    sleep 2
    xdotool mousemove --window "$winid" "$((SCREEN_WIDTH / 2))" "$((SCREEN_HEIGHT / 2))" 2>/dev/null || true
    xdotool click 1 2>/dev/null || true
    log_ok "Captured mouse into PCem (legacy grab mode)"
  fi
}

# Fallback for when CMOS could not be seeded (an unrecognised PCEM_MODEL, say):
# blind-press F1 through the POST window so the "Press F1 to continue" halt
# does not strand the pod. Deliberately skipped when CMOS is present — F1 at
# the Windows desktop opens Help, so this must not run a moment longer than
# it has to.
bios_autokey() {
  [ "$BIOS_AUTOKEY" = "1" ] || return 0
  [ "${NVR_PRESENT:-0}" = "1" ] && return 0
  log "Auto-keying F1 through POST for ${BIOS_AUTOKEY_SECONDS:=90}s (no CMOS to seed from)"
  ( for _ in $(seq 1 "$((BIOS_AUTOKEY_SECONDS / 2))"); do
      xdotool key --clearmodifiers F1 2>/dev/null || true
      sleep 2
    done ) &
}

########################################################################
# 5. Health + shutdown
########################################################################
start_health() {
  PCEM_RUN_DIR="$RUN_DIR" \
  PCEM_VNC_PORT="$VNC_PORT" \
  PCEM_AUDIO_ENABLE="$AUDIO_ENABLE" \
  PCEM_AUDIO_PORT="$AUDIO_PORT" \
  PCEM_INSTANCE_ID="$INSTANCE_ID" \
  PCEM_DISK_PATH="$DISK_PATH" \
  PCEM_GUEST_IP="$GUEST_IP" \
  PCEM_GUEST_MAC="$PCEM_MAC" \
  PCEM_NET_MODE="$PCEM_NET_MODE" \
  PCEM_PCAP_DEVICE="$PCAP_DEVICE" \
    python3 /usr/local/bin/health-server.py "$HEALTH_PORT" >"${RUN_DIR}/health.log" 2>&1 &
  echo $! > "${RUN_DIR}/health.pid"
  log_ok "Health endpoint on :${HEALTH_PORT}/health"
}

# gotcha #12: PCem only flushes its disk write-back cache on a clean exit, and
# it ignores SIGTERM/SIGINT. The one path that runs its close handler is a
# WM_DELETE_WINDOW to the wx top-level frame.
shutdown_pcem() {
  log "Shutting down…"
  local winid
  winid="$(xdotool search --name "^PCem$" 2>/dev/null | head -1 || true)"
  if [ -n "$winid" ]; then
    xdotool windowclose "$winid" 2>/dev/null || true
    for _ in $(seq 1 20); do
      kill -0 "${PCEM_PID:-0}" 2>/dev/null || { log_ok "PCem exited cleanly (disk flushed)"; break; }
      sleep 0.5
    done
  fi
  kill -9 "${PCEM_PID:-0}" 2>/dev/null || true
  exit 0
}
trap shutdown_pcem TERM INT

########################################################################
main() {
  log "PCem emulator — instance ${INSTANCE_ID}"
  ensure_disk
  check_disk_writable
  prepare_pcem_home
  setup_guest_lan
  inject_guest_identity
  inject_desktop_shortcuts
  start_guest_dhcp
  render_config
  write_global_config
  start_display
  start_vnc
  # Before PCem: OpenAL picks its backend once, at device open.
  start_audio
  start_health
  start_pcem
  place_window || true
  bios_autokey
  start_autoname

  log_ok "Ready — VNC on :${VNC_PORT}, health on :${HEALTH_PORT}"
  wait "$PCEM_PID"
  local rc=$?
  log_err "PCem exited with status ${rc}"
  tail -20 "${RUN_DIR}/pcem.log" 2>/dev/null || true
  exit "$rc"
}

main "$@"
