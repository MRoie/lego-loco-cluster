# Audio Pipeline Validation — 2026-03-27

**Task**: E3 — Audio pipeline validation (P1)  
**Depends on**: E1 (QEMU startup fix)

## Pipeline Architecture

```
┌──────────┐    ┌────────────┐    ┌───────────────────────────────────────────┐    ┌──────────────┐
│  QEMU    │───►│ PulseAudio │───►│         GStreamer Pipeline                │───►│ Backend      │
│  SB16    │    │  daemon     │    │ pulsesrc → audioconvert → audioresample  │    │ udpToWebrtc  │
│  audiodev│    │  (pa,snd0) │    │ → opusenc → rtpopuspay → udpsink :5001   │    │ port 5001    │
└──────────┘    └────────────┘    └───────────────────────────────────────────┘    └──────────────┘
```

### QEMU Audio Config

From `config/qemu.json`:
- **Device**: Sound Blaster 16 (`sb16`)
- **Backend**: PulseAudio (`pa`)

QEMU flags in `entrypoint.sh`:
```
-device sb16,audiodev=snd0 -audiodev pa,id=snd0
```

### GStreamer Pipeline (entrypoint.sh Step 6b)

```bash
gst-launch-1.0 -v \
  pulsesrc ! \
  queue max-size-time=100000000 max-size-buffers=10 leaky=downstream ! \
  audioconvert ! audioresample ! \
  audio/x-raw,rate=48000,channels=2 ! \
  opusenc bitrate=64000 frame-size=20 ! \
  rtpopuspay pt=97 ! \
  udpsink host=${AUDIO_DEST_HOST} port=${AUDIO_DEST_PORT} sync=false async=false
```

- **Codec**: Opus at 64kbps, 20ms frames
- **Sample rate**: 48kHz stereo (matches WebRTC Opus spec)
- **RTP payload type**: 97 (dynamic, matches `rtpopuspay` default)
- **Destination**: UDP `${AUDIO_DEST_HOST}:${AUDIO_DEST_PORT}` (default `127.0.0.1:5001`)

### Backend Consumer (`backend/services/udpToWebrtc.js`)

The backend binds a UDP socket on port 5001, receives RTP Opus packets, and
forwards them via `audioTrack.writeRtp(msg)` to all connected WebRTC peers.
The `RTCRtpCodecParameters` specify `audio/opus` at 48kHz stereo — matching
the GStreamer pipeline output exactly.

## Bug Fixed: Insufficient PulseAudio Ready Wait

### Problem

The original code used a static `sleep 2` before launching the GStreamer audio
pipeline. This assumed PulseAudio would have a source (monitor from QEMU's
SB16 sink) within 2 seconds of the video pipeline starting. In practice:

- QEMU's PulseAudio connection depends on guest OS boot progress
- The SB16 driver in Win98 initializes late (after GUI loads)
- On slow TCG emulation, 2 seconds is never enough

Result: `pulsesrc` would open PulseAudio's default (null) source and produce
silence, or fail entirely if no source existed.

### Fix

Replaced `sleep 2` with a polling loop (max 30s, 2s interval) that checks
`pactl list sources short` for any source in `RUNNING`, `IDLE`, or `SUSPENDED`
state. The pipeline starts as soon as a source is detected, or proceeds with
a warning after timeout.

**File**: `containers/qemu-softgpu/entrypoint.sh` (Step 6b)

## Required Packages (Dockerfile)

All installed in `containers/qemu-softgpu/Dockerfile`:
- `pulseaudio` — audio daemon
- `gstreamer1.0-tools` — `gst-launch-1.0`
- `gstreamer1.0-plugins-base` — `audioconvert`, `audioresample`
- `gstreamer1.0-plugins-good` — `rtpopuspay`, `udpsink`, `queue`
- `gstreamer1.0-plugins-bad` — `opusenc`
- `gstreamer1.0-pulseaudio` — `pulsesrc`
- `libopus-dev` — Opus codec library

## Validation Script

**File**: `scripts/validate-audio-pipeline.sh`  
**Usage**: `./scripts/validate-audio-pipeline.sh [INSTANCE_INDEX]`

Checks (via `kubectl exec`):
1. PulseAudio daemon running
2. PulseAudio has active source(s)
3. QEMU command line includes `-device sb16` and `-audiodev pa`
4. GStreamer audio pipeline process running with correct elements
5. UDP packets being emitted on port 5001

## Edge Cases & Known Issues

- **Guest audio not playing**: If Win98 hasn't loaded the SB16 driver or no
  application is producing sound, `pulsesrc` will capture silence. The pipeline
  still runs, packets still flow — they just contain silent Opus frames.
- **TCG startup latency**: On pure software emulation (no KVM), Win98 boot can
  take 60-90 seconds. The 30-second PulseAudio wait starts after the existing
  30-second QEMU init delay, so total budget is ~60s — usually enough.
- **Multiple instances**: Each container runs its own PulseAudio daemon in
  isolation. No cross-instance audio leakage.

## Cross-Team References

- **Stream Quality Lead**: VP8 video uses same UDP transport pattern (port 5000)
- **Backend Lead**: `udpToWebrtc.js` consumes both video (5000) and audio (5001)
- **Win98 Lead**: SB16 driver must be installed in the guest image for audio output
