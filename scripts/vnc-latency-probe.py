#!/usr/bin/env python3
"""Motion-to-update latency through the frontend WebSocket VNC bridge.

    vnc-latency-probe.py [ws://host:3000/proxy/vnc/instance-N/]

Run it against a guest showing the LOCO *world* (mostly static screen); the
destination-box filter tolerates ambient animation but a full-screen animated
menu drowns it. Baseline on this stack, 2026-08: p50 112 ms, p90 112 ms over
the full nginx -> backend -> Xvnc -> PCem -> guest loop. That number is the
server-side floor a browser or headset adds its own compositor and network to;
regressions here are pipeline regressions, not client ones.

Method: one WS connection, incremental FramebufferUpdateRequests. Per sample:
park the pointer, wait until the stream is quiet (>300 ms without an update
rect intersecting the parked cursor's 60x60 box; ambient animation elsewhere
does not reset the clock), then send ONE PointerEvent moving 200 px and time
from that send until the first FramebufferUpdate whose rect intersects the
DESTINATION 60x60 box. Directions alternate so the cursor shuttles between
two fixed points instead of walking off.
"""

import importlib.util
import pathlib
import socket
import struct
import sys
import time

spec = importlib.util.spec_from_file_location(
    "vncdrive", str(pathlib.Path(__file__).with_name("vnc-drive.py")))
vncdrive = importlib.util.module_from_spec(spec)
spec.loader.exec_module(vncdrive)

URL = sys.argv[1] if len(sys.argv) > 1 else "ws://localhost:3000/proxy/vnc/instance-0/"
A = (400, 550)
B = (600, 550)          # 200 px apart, clear of the track and the water
BOX = 30                # half-side of the 60x60 destination box
QUIET_S = 0.30
SAMPLES = 16


def recv_exact(sock, n):
    chunks, left = [], n
    while left:
        c = sock.recv(left)
        if not c:
            raise RuntimeError("closed")
        chunks.append(c)
        left -= len(c)
    return b"".join(chunks)


def read_msg(sock, first_byte_timeout):
    """Read one server message; None on first-byte timeout.

    Only the FIRST byte is polled with a short timeout — once a message has
    started, the rest is read with a long timeout so a poll can never split
    a message. Returns ('update', [rects]) or ('other', type)."""
    sock.settimeout(first_byte_timeout)
    try:
        t = recv_exact(sock, 1)[0]
    except socket.timeout:
        return None
    sock.settimeout(10)
    if t == 0:                                    # FramebufferUpdate
        recv_exact(sock, 1)
        (n,) = struct.unpack(">H", recv_exact(sock, 2))
        rects = []
        for _ in range(n):
            x, y, w, h, enc = struct.unpack(">HHHHi", recv_exact(sock, 12))
            if enc == 0:
                recv_exact(sock, w * h * 4)
            else:
                raise RuntimeError(f"unexpected encoding {enc}")
            rects.append((x, y, w, h))
        return ("update", rects)
    if t == 1:                                    # SetColourMapEntries
        recv_exact(sock, 3)
        (n,) = struct.unpack(">H", recv_exact(sock, 2))
        recv_exact(sock, n * 6)
    elif t == 2:                                  # Bell
        pass
    elif t == 3:                                  # ServerCutText
        recv_exact(sock, 3)
        (n,) = struct.unpack(">I", recv_exact(sock, 4))
        recv_exact(sock, n)
    else:
        raise RuntimeError(f"unexpected message type {t}")
    return ("other", t)


def intersects(rect, cx, cy):
    x, y, w, h = rect
    return x < cx + BOX and x + w > cx - BOX and y < cy + BOX and y + h > cy - BOX


def main():
    cli = vncdrive.Client(URL, timeout=20)
    print(f"connected: {cli.name} {cli.width}x{cli.height}", flush=True)
    sock = cli.sock

    def request():
        sock.sendall(struct.pack(">BBHHHH", 3, 1, 0, 0, cli.width, cli.height))

    def pointer(x, y):
        sock.sendall(struct.pack(">BBHH", 5, 0, x, y))

    request()
    pos, samples, ambient_hits = A, [], 0
    for i in range(SAMPLES):
        dest = B if pos == A else A
        # -- park and wait for quiet around the parked cursor --------------
        pointer(*pos)
        last_cursor_update = time.perf_counter()
        park_deadline = time.perf_counter() + 15
        while time.perf_counter() - last_cursor_update < QUIET_S:
            if time.perf_counter() > park_deadline:
                print(f"  sample {i}: never went quiet, proceeding anyway", flush=True)
                break
            msg = read_msg(sock, 0.05)
            if msg and msg[0] == "update":
                request()
                if any(intersects(r, *pos) for r in msg[1]):
                    last_cursor_update = time.perf_counter()
        # -- single move, time to first update touching the destination ----
        t0 = time.perf_counter()
        pointer(*dest)
        t1 = None
        sample_deadline = t0 + 5
        while t1 is None and time.perf_counter() < sample_deadline:
            msg = read_msg(sock, 0.05)
            if msg and msg[0] == "update":
                now = time.perf_counter()
                request()
                if any(intersects(r, *dest) for r in msg[1]):
                    t1 = now
                else:
                    ambient_hits += 1
        if t1 is None:
            print(f"  sample {i} {pos}->{dest}: TIMEOUT", flush=True)
        else:
            ms = (t1 - t0) * 1000
            samples.append(ms)
            print(f"  sample {i} {pos}->{dest}: {ms:.1f} ms", flush=True)
        pos = dest

    samples.sort()
    n = len(samples)
    if n:
        p50 = samples[int(0.50 * (n - 1))]
        p90 = samples[int(0.90 * (n - 1))]
        print(f"samples={n} p50={p50:.1f}ms p90={p90:.1f}ms "
              f"min={samples[0]:.1f} max={samples[-1]:.1f}", flush=True)
        print("all:", " ".join(f"{s:.1f}" for s in samples), flush=True)
        print(f"ambient updates observed during timing (non-destination rects): "
              f"{ambient_hits}", flush=True)


if __name__ == "__main__":
    main()
