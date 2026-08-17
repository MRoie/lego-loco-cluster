#!/usr/bin/env python3
"""Type this instance's name into LEGO LOCO's main-menu ticket.

The computer name reaches Windows through LOCOID.REG before boot, but the
name LEGO LOCO shows other players is game state, not registry state — it
lives in the red "ticket" on the main menu — so no offline file edit can set
it. This does it the way a player would: watch the framebuffer over RFB
until the menu appears, click the ticket's name field, clear it, type the
name. Then STOP — pressing Enter or clicking the green check would start
the game, and starting the session belongs to the player (or to whatever
automation owns that decision later).

Detection is a sparse pixel signature rather than template matching: at
1024x768 the ticket is a strongly red block around x 370-820, y 600-730
with a white name-entry strip around x 440-770, y 650-672. A few hundred
grid points sampled from a 450x130 slice of the framebuffer are cheap
enough to poll every 10 s and specific enough that nothing else in the boot
sequence (POST, the Windows boot screen, the desktop, LOCO's loading
screens) shows both zones at once.

Runs backgrounded from the entrypoint (start_autoname), so it must never
take the pod down with it: every failure path logs and exits 0. A missed
menu costs the name, never the pod.

Environment:
    LOCO_GUEST_NAME   name to type (uppercased); same value as the computer name
    AUTONAME_HOST     RFB host          (default 127.0.0.1)
    AUTONAME_PORT     RFB port          (default 5901)
    AUTONAME_MARKER   success marker    (default /run/pcem/autoname.done)
    AUTONAME_TIMEOUT  seconds to watch  (default 480)

The RFB client below is the minimal subset of scripts/vnc-drive.py (repo
root): one connection, SecurityType None, Raw encoding only. Copied rather
than imported because that driver is a host-side debugging tool that does
not ship in this image.
"""

import os
import socket
import struct
import sys
import time

RFB_VERSION = b"RFB 003.008\n"

# Signature zones in 1024x768 framebuffer coordinates (x1, y1, x2, y2),
# calibrated against a live native-resolution screenshot — NOT estimated.
# The obvious signature (a white name-entry strip) does not exist: the field
# is a red inset the same colour as the ticket, and the only white pixels in
# it are the typed glyphs themselves. What is unambiguous at this layout:
#   - two solid-red ticket strips above and below the field, colour
#     (224,80,80) — note G=80, so the threshold must be G<110, not G<80
#   - the big green confirm button to the right, solid (0,156,0)
RED_TOP = (420, 560, 740, 585)
RED_BOTTOM = (420, 625, 740, 650)
GREEN_BUTTON = (785, 565, 875, 650)
CLICK_AT = (575, 605)           # centre of the name-entry inset
ROI = (380, 550, 510, 110)      # (x, y, w, h) slice covering all three zones

KEYSYMS = {"End": 0xFF57, "BackSpace": 0xFF08, "Delete": 0xFFFF, "Shift_L": 0xFFE1}

POLL_INTERVAL = 10
KEY_DELAY = 0.08                # per-key, so a busy emulator drops nothing
CLEAR_KEYS = 24                 # the field survives reboots; wipe the old name


def log(msg):
    print("[%s] %s" % (time.strftime("%H:%M:%S", time.gmtime()), msg), flush=True)


class RFBError(RuntimeError):
    pass


class Client:
    """Just enough RFB to poll pixels and type (subset of vnc-drive.py)."""

    def __init__(self, host, port, timeout=20):
        self.sock = socket.create_connection((host, port), timeout=timeout)
        self.timeout = timeout
        self.width, self.height = self._handshake()
        # 32bpp true colour, shifts 16/8/0 — little-endian BGRX in memory,
        # which is the byte order sample() indexes below.
        pixel_format = struct.pack(
            ">BBBB HHH BBB 3x", 32, 24, 0, 1, 255, 255, 255, 16, 8, 0)
        self.sock.sendall(struct.pack(">B3x", 0) + pixel_format)   # SetPixelFormat
        self.sock.sendall(struct.pack(">BxHi", 2, 1, 0))           # SetEncodings: Raw

    def _recv(self, count):
        chunks, remaining = [], count
        while remaining:
            chunk = self.sock.recv(remaining)
            if not chunk:
                raise RFBError("connection closed")
            chunks.append(chunk)
            remaining -= len(chunk)
        return b"".join(chunks)

    def _handshake(self):
        version = self._recv(12)
        if not version.startswith(b"RFB "):
            raise RFBError("not an RFB server: %r" % version)
        self.sock.sendall(RFB_VERSION)
        count = self._recv(1)[0]
        if count == 0:
            reason_len = struct.unpack(">I", self._recv(4))[0]
            raise RFBError("refused: %s" % self._recv(reason_len).decode(errors="replace"))
        types = set(self._recv(count))
        if 1 not in types:
            raise RFBError("no SecurityType None; server offered %s" % sorted(types))
        self.sock.sendall(bytes([1]))
        if struct.unpack(">I", self._recv(4))[0] != 0:
            raise RFBError("authentication failed")
        self.sock.sendall(bytes([1]))                              # ClientInit, shared
        width, height = struct.unpack(">HH", self._recv(4))
        self._recv(16)
        name_len = struct.unpack(">I", self._recv(4))[0]
        self._recv(name_len)
        return width, height

    def close(self):
        try:
            self.sock.close()
        except OSError:
            pass

    # -- input ------------------------------------------------------------
    def pointer(self, x, y, buttons=0):
        self.sock.sendall(struct.pack(">BBHH", 5, buttons, int(x), int(y)))

    def click(self, x, y):
        # settle: the emulated mouse is relative, so the guest cursor *walks*
        # to the target; pressing early clicks wherever it happens to be.
        # hold: LOCO samples the button on its own slow loop and ignores a
        # short press (measured during vnc-drive.py's bring-up).
        self.pointer(x, y, 0)
        time.sleep(0.8)
        self.pointer(x, y, 1)
        time.sleep(0.7)
        self.pointer(x, y, 0)
        time.sleep(0.2)

    def key(self, keysym, down):
        self.sock.sendall(struct.pack(">BBxxI", 4, 1 if down else 0, keysym))

    def tap(self, keysym, delay=KEY_DELAY):
        self.key(keysym, True)
        time.sleep(delay / 2)
        self.key(keysym, False)
        time.sleep(delay)

    def type_text(self, text):
        for ch in text:
            if "A" <= ch <= "Z":
                # The keysym alone does not shift the guest — without a held
                # Shift, Windows sees lowercase (same gotcha vnc-drive.py hit).
                self.key(KEYSYMS["Shift_L"], True)
                time.sleep(KEY_DELAY / 2)
                self.tap(ord(ch))
                self.key(KEYSYMS["Shift_L"], False)
                time.sleep(KEY_DELAY / 2)
            else:
                self.tap(ord(ch))

    # -- pixels -----------------------------------------------------------
    def grab(self, x, y, w, h):
        """One non-incremental FramebufferUpdate of a rect, as BGRX bytes.

        Requesting just the 450x130 signature slice instead of the whole 3 MB
        frame keeps the watcher invisible next to PCem itself.
        """
        self.sock.sendall(struct.pack(">BBHHHH", 3, 0, x, y, w, h))
        buf = bytearray(w * h * 4)
        painted = 0
        deadline = time.time() + self.timeout
        while painted < w * h and time.time() < deadline:
            msg = self._recv(1)[0]
            if msg != 0:
                self._skip(msg)
                continue
            self._recv(1)
            for _ in range(struct.unpack(">H", self._recv(2))[0]):
                rx, ry, rw, rh, enc = struct.unpack(">HHHHi", self._recv(12))
                if enc != 0:
                    raise RFBError("encoding %d despite Raw-only SetEncodings" % enc)
                data = self._recv(rw * rh * 4)
                # Rects arrive in framebuffer coordinates and the server may
                # send more than asked for; keep only the overlap.
                for row in range(rh):
                    fy = ry + row
                    if not y <= fy < y + h:
                        continue
                    sx, ex = max(rx, x), min(rx + rw, x + w)
                    if sx >= ex:
                        continue
                    src = (row * rw + (sx - rx)) * 4
                    dst = ((fy - y) * w + (sx - x)) * 4
                    buf[dst:dst + (ex - sx) * 4] = data[src:src + (ex - sx) * 4]
                    painted += ex - sx
        return buf

    def _skip(self, msg_type):
        if msg_type == 1:      # SetColourMapEntries
            self._recv(3)
            self._recv(struct.unpack(">H", self._recv(2))[0] * 6)
        elif msg_type == 2:    # Bell
            pass
        elif msg_type == 3:    # ServerCutText
            self._recv(3)
            self._recv(struct.unpack(">I", self._recv(4))[0])
        else:
            raise RFBError("unexpected server message type %d" % msg_type)


def zone_fraction(buf, zone, step_x, step_y, pred, exclude=None):
    """Fraction of grid points inside `zone` whose pixel satisfies pred."""
    rx, ry, rw, _rh = ROI
    x1, y1, x2, y2 = zone
    total = hits = 0
    for y in range(y1, y2, step_y):
        for x in range(x1, x2, step_x):
            if exclude and exclude[0] <= x < exclude[2] and exclude[1] <= y < exclude[3]:
                continue
            p = ((y - ry) * rw + (x - rx)) * 4
            b, g, r = buf[p], buf[p + 1], buf[p + 2]
            total += 1
            if pred(r, g, b):
                hits += 1
    return hits / total if total else 0.0


def menu_visible(buf):
    is_red = lambda r, g, b: r > 180 and g < 110 and b < 110
    is_green = lambda r, g, b: g > 120 and r < 100 and b < 100
    red_top = zone_fraction(buf, RED_TOP, 16, 5, is_red)
    red_bottom = zone_fraction(buf, RED_BOTTOM, 16, 5, is_red)
    green = zone_fraction(buf, GREEN_BUTTON, 8, 5, is_green)
    log("signature: red %.2f/%.2f green %.2f" % (red_top, red_bottom, green))
    # Measured on the live menu: 1.00 / 1.00 / 0.86. Thresholds sit well
    # below that but far above anything the desktop or the in-game world
    # produces in these zones.
    return red_top >= 0.6 and red_bottom >= 0.6 and green >= 0.5


def name_instance(client, name):
    client.click(*CLICK_AT)
    # LOCO's ticket field is a custom control that ignores the End keysym, so
    # backspaces alone only clear LEFT of wherever the click landed — a
    # leftover glyph to the right survived on a live run. Sweep both ways.
    client.tap(KEYSYMS["End"])
    for _ in range(CLEAR_KEYS):
        client.tap(KEYSYMS["BackSpace"])
    for _ in range(CLEAR_KEYS):
        client.tap(KEYSYMS["Delete"])
    client.type_text(name)
    # Deliberately NO Enter and NO green check — either one starts the game.


def main():
    name = os.environ.get("LOCO_GUEST_NAME", "").strip().upper()
    if not name:
        log("LOCO_GUEST_NAME is empty — nothing to type")
        return
    host = os.environ.get("AUTONAME_HOST", "127.0.0.1")
    port = int(os.environ.get("AUTONAME_PORT", "5901"))
    marker = os.environ.get("AUTONAME_MARKER", "/run/pcem/autoname.done")
    deadline = time.time() + float(os.environ.get("AUTONAME_TIMEOUT", "480"))

    client = None
    while time.time() < deadline:
        try:
            if client is None:
                client = Client(host, port)
                log("connected to %s:%s (%dx%d)"
                    % (host, port, client.width, client.height))
                if client.width < GREEN_BUTTON[2] or client.height < RED_BOTTOM[3]:
                    # The signature is defined at 1024x768; on a smaller
                    # framebuffer the sample would index out of frame.
                    log("framebuffer too small for the 1024x768 signature — giving up")
                    return
            if menu_visible(client.grab(*ROI)):
                log("main menu detected — naming this instance %r" % name)
                name_instance(client, name)
                with open(marker, "w") as fh:
                    fh.write(name + "\n")
                log("typed %r into the ticket; marker written to %s" % (name, marker))
                return
        except (RFBError, OSError) as exc:
            log("transient: %s — reconnecting" % exc)
            if client is not None:
                client.close()
            client = None
        time.sleep(POLL_INTERVAL)
    log("menu never appeared before the deadline — leaving the guest untouched")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:  # noqa: BLE001 — this must never crash the pod
        log("unexpected: %r — exiting 0 anyway" % exc)
    sys.exit(0)
