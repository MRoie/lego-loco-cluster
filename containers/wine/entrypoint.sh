#!/usr/bin/env bash
set -euo pipefail

BRIDGE=${BRIDGE:-loco-br}
TAP_IF=${TAP_IF:-tap0}
APP=${APP:-/opt/lego-loco/lego.exe}

# Wait until an X11 window matching a name appears
wait_for_window() {
  local name=$1
  for _ in {1..30}; do
    if xdotool search --name "$name" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  echo "⚠️  Timed out waiting for window $name" >&2
}

pulseaudio --start --exit-idle-time=-1
echo "🔈 PulseAudio started"

ip tuntap add "$TAP_IF" mode tap || true
ip link set "$TAP_IF" up
if ip link show "$BRIDGE" &>/dev/null; then
  ip link set "$TAP_IF" master "$BRIDGE"
fi

# Start Wine application
wine "$APP" &
EMU_PID=$!

# Wait for the game window instead of a fixed sleep
wait_for_window "Lego Loco"

gst-launch-1.0 -v \
  ximagesrc use-damage=0 ! videoconvert ! queue ! vp8enc deadline=1 ! rtpvp8pay ! application/x-rtp,media=video,encoding-name=VP8,payload=96 ! webrtcbin bundle-policy=max-bundle name=wb \
  pulsesrc ! audioconvert ! audioresample ! opusenc ! rtpopuspay ! application/x-rtp,media=audio,encoding-name=OPUS,payload=97 ! wb. \
  wb. ! fakesink

wait $EMU_PID
