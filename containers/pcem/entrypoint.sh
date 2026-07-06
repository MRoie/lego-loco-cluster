#!/usr/bin/env bash
set -euo pipefail

BRIDGE=${BRIDGE:-loco-br}
TAP_IF=${TAP_IF:-tap0}
DISK=${DISK:-/images/win98.img}

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

pcem --config /pcem.cfg --hda "$DISK" &
EMU_PID=$!

# Wait for the PCem window instead of sleeping
wait_for_window "PCem"

# Enhanced PCem container with Lego Loco 1024x768 streaming and SRE monitoring
echo "🚀 Starting PCem emulator with 1024x768 WebRTC streaming for Lego Loco"

gst-launch-1.0 -v \
  ximagesrc use-damage=0 ! \
  queue max-size-time=100000000 max-size-buffers=5 leaky=downstream ! \
  videoconvert ! \
  queue max-size-time=100000000 max-size-buffers=5 leaky=downstream ! \
  videoscale ! \
  video/x-raw,width=1024,height=768,framerate=25/1 ! \
  queue max-size-time=100000000 max-size-buffers=5 leaky=downstream ! \
  vp8enc deadline=1 target-bitrate=1200000 ! \
  queue max-size-time=100000000 max-size-buffers=5 leaky=downstream ! \
  rtpvp8pay ! \
  application/x-rtp,media=video,encoding-name=VP8,payload=96 ! \
  webrtcbin bundle-policy=max-bundle name=wb \
  pulsesrc ! \
  queue max-size-time=100000000 max-size-buffers=5 leaky=downstream ! \
  audioconvert ! \
  queue max-size-time=100000000 max-size-buffers=5 leaky=downstream ! \
  audioresample ! \
  queue max-size-time=100000000 max-size-buffers=5 leaky=downstream ! \
  opusenc ! \
  queue max-size-time=100000000 max-size-buffers=5 leaky=downstream ! \
  rtpopuspay ! \
  application/x-rtp,media=audio,encoding-name=OPUS,payload=97 ! \
  wb. \
  wb. ! fakesink &

GSTREAMER_PID=$!
echo "🎯 PCem WebRTC stream started with 1024x768@25fps VP8 encoding (PID: $GSTREAMER_PID)"

# SRE Health Monitoring for PCem
sleep 3
if kill -0 $GSTREAMER_PID 2>/dev/null; then
  echo "✅ PCem stream health check passed - 1024x768 WebRTC stream active"
else
  echo "⚠️  PCem stream health check failed - WebRTC streaming may be unstable"
fi

wait $EMU_PID
