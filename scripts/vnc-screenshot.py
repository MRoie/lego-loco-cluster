#!/usr/bin/env python3
"""Grab a PNG from a raw RFB (VNC) server — no client libraries required.

This speaks the same thing the backend's WebSocket bridge pipes to noVNC
(backend/server.js createVNCBridge), so a successful capture proves the whole
emulator-side path: framebuffer -> x11vnc -> TCP 5901 -> RFB handshake ->
pixels. Handy for CI, for checking what an emulator pod is actually showing,
and for debugging "the tile is black" without a browser.

    scripts/vnc-screenshot.py localhost:5901 out.png
    scripts/vnc-screenshot.py localhost:5901 out.png --wait 5

Pillow is used if available; otherwise a PNG is written with zlib directly, so
this has no hard third-party dependency.
"""

import argparse
import socket
import struct
import sys
import time
import zlib

RFB_VERSION = b"RFB 003.008\n"


class RFBError(RuntimeError):
    pass


def recv_exactly(sock, count):
    chunks = []
    remaining = count
    while remaining:
        chunk = sock.recv(remaining)
        if not chunk:
            raise RFBError(f"connection closed with {remaining} of {count} bytes outstanding")
        chunks.append(chunk)
        remaining -= len(chunk)
    return b"".join(chunks)


def handshake(sock, password=None):
    server_version = recv_exactly(sock, 12)
    if not server_version.startswith(b"RFB "):
        raise RFBError(f"not an RFB server, got {server_version!r}")
    sock.sendall(RFB_VERSION)

    count = recv_exactly(sock, 1)[0]
    if count == 0:
        reason_len = struct.unpack(">I", recv_exactly(sock, 4))[0]
        raise RFBError(f"server refused: {recv_exactly(sock, reason_len).decode(errors='replace')}")
    types = set(recv_exactly(sock, count))

    if 1 in types:                      # None
        sock.sendall(bytes([1]))
    else:
        raise RFBError(f"no supported security type in {sorted(types)} (this tool only does None)")

    result = struct.unpack(">I", recv_exactly(sock, 4))[0]
    if result != 0:
        raise RFBError("authentication failed")

    sock.sendall(bytes([1]))            # ClientInit, shared=1
    width, height = struct.unpack(">HH", recv_exactly(sock, 4))
    recv_exactly(sock, 16)              # server pixel format (we override it)
    name_len = struct.unpack(">I", recv_exactly(sock, 4))[0]
    name = recv_exactly(sock, name_len).decode(errors="replace")
    return width, height, name


def configure(sock):
    """Pin the pixel format to 32bpp BGRX and the encoding to Raw.

    Pinning both is what keeps the decode deterministic — servers are free to
    pick their own otherwise, which is how channel-order bugs sneak in.
    """
    pixel_format = struct.pack(
        ">BBBB HHH BBB 3x",
        32,      # bits-per-pixel
        24,      # depth
        0,       # big-endian-flag
        1,       # true-colour-flag
        255, 255, 255,   # red/green/blue max
        16, 8, 0,        # red/green/blue shift
    )
    sock.sendall(struct.pack(">B3x", 0) + pixel_format)          # SetPixelFormat
    sock.sendall(struct.pack(">BxHi", 2, 1, 0))                  # SetEncodings: Raw


def request_full_update(sock, width, height):
    sock.sendall(struct.pack(">BBHHHH", 3, 0, 0, 0, width, height))


def read_update(sock, width, height, timeout):
    """Read FramebufferUpdate messages until the whole screen has been painted."""
    framebuffer = bytearray(width * height * 4)
    painted = 0
    deadline = time.time() + timeout

    while painted < width * height and time.time() < deadline:
        msg_type = recv_exactly(sock, 1)[0]
        if msg_type != 0:                       # only FramebufferUpdate is interesting
            skip_other_message(sock, msg_type)
            continue

        recv_exactly(sock, 1)
        n_rects = struct.unpack(">H", recv_exactly(sock, 2))[0]
        for _ in range(n_rects):
            x, y, w, h, encoding = struct.unpack(">HHHHi", recv_exactly(sock, 12))
            if encoding != 0:
                raise RFBError(f"server used encoding {encoding} despite Raw-only SetEncodings")
            data = recv_exactly(sock, w * h * 4)
            for row in range(h):
                dst = ((y + row) * width + x) * 4
                src = row * w * 4
                framebuffer[dst:dst + w * 4] = data[src:src + w * 4]
            painted += w * h

    if painted == 0:
        raise RFBError("server sent no pixels")
    return framebuffer


def skip_other_message(sock, msg_type):
    if msg_type == 1:                           # SetColourMapEntries
        recv_exactly(sock, 3)
        n = struct.unpack(">H", recv_exactly(sock, 2))[0]
        recv_exactly(sock, n * 6)
    elif msg_type == 2:                         # Bell
        pass
    elif msg_type == 3:                         # ServerCutText
        recv_exactly(sock, 3)
        n = struct.unpack(">I", recv_exactly(sock, 4))[0]
        recv_exactly(sock, n)
    else:
        raise RFBError(f"unexpected server message type {msg_type}")


def to_rgb_rows(framebuffer, width, height):
    """BGRX (little-endian 32bpp with our shifts) -> per-row RGB bytes."""
    rows = []
    for y in range(height):
        base = y * width * 4
        row = bytearray(width * 3)
        for x in range(width):
            p = base + x * 4
            row[x * 3 + 0] = framebuffer[p + 2]
            row[x * 3 + 1] = framebuffer[p + 1]
            row[x * 3 + 2] = framebuffer[p + 0]
        rows.append(bytes(row))
    return rows


def write_png(path, rows, width, height):
    try:
        from PIL import Image
    except ImportError:
        pass
    else:
        Image.frombytes("RGB", (width, height), b"".join(rows)).save(path)
        return

    def chunk(tag, payload):
        return (struct.pack(">I", len(payload)) + tag + payload
                + struct.pack(">I", zlib.crc32(tag + payload) & 0xFFFFFFFF))

    raw = b"".join(b"\x00" + row for row in rows)
    png = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(raw, 6))
           + chunk(b"IEND", b""))
    with open(path, "wb") as fh:
        fh.write(png)


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("target", help="host:port of the VNC server (port defaults to 5901)")
    parser.add_argument("output", help="PNG file to write")
    parser.add_argument("--wait", type=float, default=0,
                        help="seconds to wait after connecting before requesting pixels")
    parser.add_argument("--timeout", type=float, default=20, help="per-operation timeout")
    args = parser.parse_args()

    host, _, port = args.target.partition(":")
    port = int(port or 5901)

    with socket.create_connection((host, port), timeout=args.timeout) as sock:
        sock.settimeout(args.timeout)
        width, height, name = handshake(sock)
        configure(sock)
        if args.wait:
            time.sleep(args.wait)
        request_full_update(sock, width, height)
        framebuffer = read_update(sock, width, height, args.timeout)

    write_png(args.output, to_rgb_rows(framebuffer, width, height), width, height)
    print(f'{name}: {width}x{height} -> {args.output}')


if __name__ == "__main__":
    try:
        main()
    except (RFBError, OSError) as exc:
        sys.exit(f"vnc-screenshot: {exc}")
