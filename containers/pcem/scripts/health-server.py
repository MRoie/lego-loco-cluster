#!/usr/bin/env python3
"""Health/readiness endpoint for the PCem emulator container.

The chart's probes hit :8080/health (startup) and :8080/ (liveness and
readiness), and the frontend uses the same JSON to decide whether an instance
is bootable, booting or live — so "ready" here has to mean "a browser can
connect and see the machine", not merely "the process is running".

  ready  = PCem alive AND something is LISTENing on the VNC port
           AND the SDL render window exists on the X server
"""

import http.server
import json
import os
import subprocess
import sys
import threading
import time

RUN_DIR = os.environ.get("PCEM_RUN_DIR", "/run/pcem")
# The backend's ProbingService gives each probe 2000 ms (backend/services/
# probingService.js) and marks the instance degraded on timeout — which drops
# its tile out of the frontend grid. Checking the X server and the VNC socket
# inline can exceed that on a CPU-saturated pod, so state is sampled on a
# background thread and requests are served from the last snapshot.
SAMPLE_INTERVAL = float(os.environ.get("PCEM_HEALTH_SAMPLE_INTERVAL", "2"))
VNC_PORT = int(os.environ.get("PCEM_VNC_PORT", "5901"))
AUDIO_ENABLE = os.environ.get("PCEM_AUDIO_ENABLE", "1") == "1"
AUDIO_PORT = int(os.environ.get("PCEM_AUDIO_PORT", "5902"))
INSTANCE_ID = os.environ.get("PCEM_INSTANCE_ID", "pcem-0")
DISK_PATH = os.environ.get("PCEM_DISK_PATH", "")
DISPLAY = os.environ.get("DISPLAY", ":99")
GUEST_IP = os.environ.get("PCEM_GUEST_IP", "")
GUEST_MAC = os.environ.get("PCEM_GUEST_MAC", "")
NET_MODE = os.environ.get("PCEM_NET_MODE", "none")
PCAP_DEVICE = os.environ.get("PCEM_PCAP_DEVICE", "")

STARTED_AT = time.time()


def _pid_alive(name):
    try:
        with open(os.path.join(RUN_DIR, f"{name}.pid")) as fh:
            pid = int(fh.read().strip())
    except (OSError, ValueError):
        return False, None
    try:
        os.kill(pid, 0)
        return True, pid
    except OSError:
        return False, pid


def _port_listening(port):
    """Is anything LISTENing on `port`? Read from /proc, never by connecting.

    Actually dialling the VNC port would be a much simpler check and is what
    this used to do — but every such connection is a real RFB session as far as
    x11vnc is concerned. It runs its WebSocket sniffing against the socket,
    logs `webSocketsHandshake: unknown connection error` when the prober hangs
    up, and with a probe every couple of seconds it eventually stops answering
    new connections altogether — so the health check ends up causing the
    outage it is meant to detect. backend/services/probingService.js carries a
    comment about removing exactly this probe for the same reason.
    """
    needle = f"{port:04X}"
    for proc in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(proc) as fh:
                next(fh, None)                       # header
                for line in fh:
                    fields = line.split()
                    if len(fields) < 4:
                        continue
                    local, state = fields[1], fields[3]
                    if state == "0A" and local.endswith(":" + needle):   # 0A = LISTEN
                        return True
        except OSError:
            continue
    return False


_window_id = None


def _sdl_window():
    """Title of PCem's SDL window, which carries its live speed percentage.

    e.g. "PCem v17 - 100% - FIC VA-503+ - Pentium MMX 200 - Click to capture mouse"

    The window id is cached after the first hit: searching the whole X server on
    every probe is the expensive half, and the id is stable for the life of the
    process.
    """
    global _window_id

    def run(args):
        return subprocess.run(
            args, capture_output=True, text=True, timeout=10,
            env={**os.environ, "DISPLAY": DISPLAY},
        ).stdout.strip()

    try:
        if _window_id:
            title = run(["xdotool", "getwindowname", _window_id])
            if title:
                return title
            _window_id = None      # window went away; fall through and re-search

        found = run(["xdotool", "search", "--name", "^PCem v17"]).splitlines()
        if not found:
            return None
        _window_id = found[-1]
        return run(["xdotool", "getwindowname", _window_id]) or None
    except (OSError, subprocess.SubprocessError):
        return None


def _emulated_speed(title):
    if not title:
        return None
    for part in title.split(" - "):
        part = part.strip()
        if part.endswith("%"):
            try:
                return int(part[:-1])
            except ValueError:
                return None
    return None


def _carrier(dev):
    """1 = the link has carrier, 0 = it does not, None = no such device.

    Worth reporting rather than assuming: a tap device with nothing holding its
    /dev/net/tun fd reads 0 here while looking perfectly plumbed to `ip link`,
    and every frame the bridge sends toward the guest is silently dropped.
    """
    if not dev:
        return None
    try:
        with open("/sys/class/net/%s/carrier" % dev) as fh:
            return int(fh.read().strip())
    except (OSError, ValueError):
        return None


def status():
    pcem_alive, pcem_pid = _pid_alive("pcem")
    vnc_up = _port_listening(VNC_PORT)
    title = _sdl_window() if pcem_alive else None
    pulse_alive, pulse_pid = _pid_alive("pulse")

    body = {
        "instance": INSTANCE_ID,
        "emulator": "pcem",
        "uptime_seconds": round(time.time() - STARTED_AT, 1),
        "pcem": {"running": pcem_alive, "pid": pcem_pid, "window_title": title},
        "video": {
            "vnc_port": VNC_PORT,
            "vnc_available": vnc_up,
            "display": DISPLAY,
            "emulated_speed_percent": _emulated_speed(title),
        },
        "disk": {
            "path": DISK_PATH,
            "present": bool(DISK_PATH) and os.path.exists(DISK_PATH),
        },
        # Guest audio: the in-pod PulseAudio daemon and its raw-PCM tap.
        # Deliberately kept out of "ready" below — video must never depend on
        # audio, so a dead daemon degrades sound and nothing else. Same
        # passive /proc/net/tcp check as VNC: dialling the PCM port would open
        # a real capture stream on module-simple-protocol-tcp every probe.
        "audio": {
            "enabled": AUDIO_ENABLE,
            "pulse_running": pulse_alive,
            "pulse_pid": pulse_pid,
            "pcm_port": AUDIO_PORT,
            "pcm_available": AUDIO_ENABLE and _port_listening(AUDIO_PORT),
        },
        # The address other guests reach this one on — what a player types into
        # LEGO LOCO's TCP/IP join box to join this instance's game. It is a
        # reservation keyed on the guest MAC, so it is knowable before the guest
        # has finished booting and stable across restarts.
        "guest_network": {
            "ip": GUEST_IP or None,
            "mac": GUEST_MAC or None,
            "mode": NET_MODE,
            "pcap_device": PCAP_DEVICE or None,
            "carrier": _carrier(PCAP_DEVICE),
        },
    }
    body["ready"] = bool(pcem_alive and vnc_up and title)
    body["status"] = "ready" if body["ready"] else ("booting" if pcem_alive else "error")
    return body


_snapshot = None
_snapshot_lock = threading.Lock()


def _sampler():
    global _snapshot
    while True:
        try:
            sampled = status()
        except Exception as exc:                      # never let the thread die
            sampled = {"ready": False, "status": "error", "error": str(exc),
                       "pcem": {"running": False}}
        with _snapshot_lock:
            _snapshot = sampled
        time.sleep(SAMPLE_INTERVAL)


def current():
    with _snapshot_lock:
        return dict(_snapshot) if _snapshot else None


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def do_GET(self):  # noqa: N802 — BaseHTTPRequestHandler API
        body = current()
        if body is None:                              # first sample not in yet
            body = {"ready": False, "status": "starting", "pcem": {"running": False}}
        # Liveness ("/") must not flap while the guest is still booting;
        # only readiness ("/health", "/ready") gates traffic.
        if self.path.rstrip("/") in ("", "/"):
            code = 200 if body["pcem"]["running"] else 503
        else:
            code = 200 if body["ready"] else 503

        payload = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def log_message(self, *args):  # silence per-request probe noise
        pass


def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
    threading.Thread(target=_sampler, daemon=True).start()
    http.server.ThreadingHTTPServer(("0.0.0.0", port), Handler).serve_forever()


if __name__ == "__main__":
    main()
