#!/usr/bin/env python3
"""Drive a VNC server the way a browser does — absolute pointer, real keys.

`vnc-screenshot.py` proves pixels come out; this proves input goes in, over the
same raw RFB stream the backend bridges to noVNC. Everything happens on ONE
connection so a sequence of actions behaves like a real session rather than a
series of reconnects (x11vnc in particular treats each connect as a new client).

RFB PointerEvent carries an ABSOLUTE position, which is what makes tablet-style
pointing possible at all: the client says "the pointer is here", never "move by
this much".

    scripts/vnc-drive.py localhost:5901 shot before.png
    scripts/vnc-drive.py localhost:5901 move 400 300 click 400 300 shot after.png
    scripts/vnc-drive.py localhost:5901 key Escape sleep 1 shot menu.png
    scripts/vnc-drive.py localhost:5901 cursor          # where is the guest cursor?

Actions (applied in order):
    move X Y            absolute pointer move
    click X Y [BUTTON]  move then press+release (button defaults to 1)
    dblclick X Y        move then two presses inside the double-click window
    down X Y [BUTTON]   press and hold at X,Y
    up X Y [BUTTON]     release at X,Y
    drag X1 Y1 X2 Y2    press at 1, move to 2, release
    key NAME            press+release a key (X keysym name, e.g. Escape, Return, F1, a)
    keydown NAME        press and hold a key
    keyup NAME          release a key
    combo A+B[+C]       hold A (and B), tap the last — e.g. combo Control_L+Escape
    text STRING         type a literal string (Shift handled automatically)
    clear               empty the focused edit control
    sleep SECONDS       wait
    shot FILE           write a PNG of the current framebuffer
    cursor              print the located guest cursor position as "cursor X Y"
"""

import argparse
import socket
import struct
import sys
import time
import zlib

RFB_VERSION = b"RFB 003.008\n"

# Enough of the X keysym table to drive an installer and a game menu.
KEYSYMS = {
    "BackSpace": 0xFF08, "Tab": 0xFF09, "Return": 0xFF0D, "Enter": 0xFF0D,
    "Escape": 0xFF1B, "Delete": 0xFFFF, "Home": 0xFF50, "Left": 0xFF51,
    "Up": 0xFF52, "Right": 0xFF53, "Down": 0xFF54, "Page_Up": 0xFF55,
    "Page_Down": 0xFF56, "End": 0xFF57, "Insert": 0xFF63, "space": 0x0020,
    "Control_L": 0xFFE3, "Shift_L": 0xFFE1, "Alt_L": 0xFFE9, "Super_L": 0xFFEB,
}
for _i in range(1, 13):
    KEYSYMS[f"F{_i}"] = 0xFFBE + _i - 1


class RFBError(RuntimeError):
    pass


class Client:
    def __init__(self, host, port, timeout=20, key_delay=0.06, settle=0.7, hold=0.6):
        self.key_delay = key_delay
        self.settle = settle
        # LEGO LOCO ignores a 200 ms press; it samples the button on its own
        # slow polling loop, so the press has to outlast one of its frames.
        self.hold = hold
        self.sock = socket.create_connection((host, port), timeout=timeout)
        self.sock.settimeout(timeout)
        self.timeout = timeout
        self.buttons = 0
        self.x = 0
        self.y = 0
        self.width, self.height, self.name = self._handshake()
        self._configure()

    # -- protocol ---------------------------------------------------------
    def _recv(self, count):
        chunks, remaining = [], count
        while remaining:
            chunk = self.sock.recv(remaining)
            if not chunk:
                raise RFBError(f"connection closed with {remaining}/{count} bytes outstanding")
            chunks.append(chunk)
            remaining -= len(chunk)
        return b"".join(chunks)

    def _handshake(self):
        version = self._recv(12)
        if not version.startswith(b"RFB "):
            raise RFBError(f"not an RFB server, got {version!r}")
        self.sock.sendall(RFB_VERSION)

        count = self._recv(1)[0]
        if count == 0:
            reason_len = struct.unpack(">I", self._recv(4))[0]
            raise RFBError(f"server refused: {self._recv(reason_len).decode(errors='replace')}")
        types = set(self._recv(count))
        if 1 not in types:
            raise RFBError(f"only the None security type is supported; server offered {sorted(types)}")
        self.sock.sendall(bytes([1]))
        if struct.unpack(">I", self._recv(4))[0] != 0:
            raise RFBError("authentication failed")

        self.sock.sendall(bytes([1]))                      # ClientInit, shared
        width, height = struct.unpack(">HH", self._recv(4))
        self._recv(16)
        name_len = struct.unpack(">I", self._recv(4))[0]
        return width, height, self._recv(name_len).decode(errors="replace")

    def _configure(self):
        pixel_format = struct.pack(
            ">BBBB HHH BBB 3x", 32, 24, 0, 1, 255, 255, 255, 16, 8, 0)
        self.sock.sendall(struct.pack(">B3x", 0) + pixel_format)   # SetPixelFormat
        self.sock.sendall(struct.pack(">BxHi", 2, 1, 0))           # SetEncodings: Raw

    # -- input ------------------------------------------------------------
    def pointer(self, x, y, buttons=None):
        if buttons is not None:
            self.buttons = buttons
        self.x, self.y = int(x), int(y)
        self.sock.sendall(struct.pack(">BBHH", 5, self.buttons, self.x, self.y))

    def click(self, x, y, button=1):
        """Move, let the guest cursor catch up, then press.

        The emulated mouse is relative, so the guest cursor walks to the target
        a few pixels per poll rather than teleporting. Pressing too early
        clicks wherever it happens to be — which looks exactly like a click
        that was ignored. `settle` is that travel time.
        """
        mask = 1 << (button - 1)
        self.pointer(x, y, 0)
        time.sleep(self.settle)
        self.pointer(x, y, mask)
        time.sleep(self.hold)
        self.pointer(x, y, 0)
        time.sleep(0.1)

    def dblclick(self, x, y, button=1):
        """Two presses inside the guest's double-click window.

        `click` twice is far too slow: it settles and holds each time, so the
        presses land seconds apart and read as two separate single clicks.
        """
        mask = 1 << (button - 1)
        self.pointer(x, y, 0)
        time.sleep(self.settle)
        for _ in range(2):
            self.pointer(x, y, mask)
            time.sleep(0.08)
            self.pointer(x, y, 0)
            time.sleep(0.08)

    def key(self, name, down=None):
        code = KEYSYMS.get(name)
        if code is None:
            if len(name) != 1:
                raise RFBError(f"unknown key name {name!r}")
            code = ord(name)
        if down is None:
            self.key(name, True)
            time.sleep(0.05)
            self.key(name, False)
            return
        self.sock.sendall(struct.pack(">BBxxI", 4, 1 if down else 0, code))

    # Characters that need Shift held on a US layout. Without this, typing
    # "C:\\DRIVERS" arrives as "c;\\drivers" — the keysym alone does not tell
    # the guest to shift, and a wrong path is silently accepted.
    SHIFTED = set('~!@#$%^&*()_+{}|:"<>?') | set(chr(c) for c in range(ord('A'), ord('Z') + 1))

    def text(self, string):
        for ch in string:
            name = {" ": "space", "\n": "Return", "\t": "Tab"}.get(ch, ch)
            if ch in self.SHIFTED:
                self.key("Shift_L", True)
                time.sleep(self.key_delay / 2)
                self.key(name)
                time.sleep(self.key_delay / 2)
                self.key("Shift_L", False)
            else:
                self.key(name)
            time.sleep(self.key_delay)

    def clear_field(self):
        """Empty the focused edit control.

        Belt and braces: go to the end and backspace, then to the start and
        delete. Individual keystrokes do get dropped on a busy emulator, and a
        half-cleared path is worse than no path at all because it looks like it
        worked.
        """
        self.key("End")
        for _ in range(40):
            self.key("BackSpace")
            time.sleep(self.key_delay / 3)
        self.key("Home")
        for _ in range(40):
            self.key("Delete")
            time.sleep(self.key_delay / 3)

    # -- framebuffer ------------------------------------------------------
    def framebuffer(self, settle=0.4):
        time.sleep(settle)
        self.sock.sendall(struct.pack(">BBHHHH", 3, 0, 0, 0, self.width, self.height))
        buf = bytearray(self.width * self.height * 4)
        painted = 0
        deadline = time.time() + self.timeout
        while painted < self.width * self.height and time.time() < deadline:
            msg = self._recv(1)[0]
            if msg != 0:
                self._skip(msg)
                continue
            self._recv(1)
            for _ in range(struct.unpack(">H", self._recv(2))[0]):
                x, y, w, h, enc = struct.unpack(">HHHHi", self._recv(12))
                if enc != 0:
                    raise RFBError(f"server used encoding {enc} despite Raw-only SetEncodings")
                data = self._recv(w * h * 4)
                for row in range(h):
                    dst = ((y + row) * self.width + x) * 4
                    src = row * w * 4
                    buf[dst:dst + w * 4] = data[src:src + w * 4]
                painted += w * h
        if painted == 0:
            raise RFBError("server sent no pixels")
        return buf

    def _skip(self, msg_type):
        if msg_type == 1:
            self._recv(3)
            self._recv(struct.unpack(">H", self._recv(2))[0] * 6)
        elif msg_type == 2:
            pass
        elif msg_type == 3:
            self._recv(3)
            self._recv(struct.unpack(">I", self._recv(4))[0])
        else:
            raise RFBError(f"unexpected server message type {msg_type}")


def find_cursor(buf, width, height):
    """Locate the guest's white arrow cursor against the Win98 desktop.

    The desktop is a flat saturated blue, so "bright and not blue" isolates the
    pointer well. Returns the topmost-leftmost pixel of the largest such
    cluster — the arrow's tip — or None.
    """
    hits = []
    for y in range(0, height):
        row = y * width * 4
        for x in range(0, width):
            p = row + x * 4
            b, g, r = buf[p], buf[p + 1], buf[p + 2]
            if r > 200 and g > 200 and b > 200:
                hits.append((x, y))
    if not hits:
        return None
    # The arrow is a compact cluster; ignore stray white UI pixels by taking the
    # densest 16x16 cell and reporting its top-left-most white pixel.
    cells = {}
    for x, y in hits:
        cells.setdefault((x // 16, y // 16), []).append((x, y))
    best = max(cells.values(), key=len)
    return min(best, key=lambda p: (p[1], p[0]))


def to_png(buf, width, height, path):
    rows = []
    for y in range(height):
        base = y * width * 4
        row = bytearray(width * 3)
        for x in range(width):
            p = base + x * 4
            row[x * 3], row[x * 3 + 1], row[x * 3 + 2] = buf[p + 2], buf[p + 1], buf[p]
        rows.append(bytes(row))
    try:
        from PIL import Image
    except ImportError:
        def chunk(tag, payload):
            return (struct.pack(">I", len(payload)) + tag + payload
                    + struct.pack(">I", zlib.crc32(tag + payload) & 0xFFFFFFFF))
        raw = b"".join(b"\x00" + r for r in rows)
        with open(path, "wb") as fh:
            fh.write(b"\x89PNG\r\n\x1a\n"
                     + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
                     + chunk(b"IDAT", zlib.compress(raw, 6))
                     + chunk(b"IEND", b""))
    else:
        Image.frombytes("RGB", (width, height), b"".join(rows)).save(path)


def run_actions(client, actions):
    i = 0
    while i < len(actions):
        verb = actions[i]
        if verb == "move":
            client.pointer(actions[i + 1], actions[i + 2]); i += 3
        elif verb in ("click", "down", "up"):
            x, y = actions[i + 1], actions[i + 2]
            i += 3
            button = 1
            if i < len(actions) and actions[i].isdigit() and len(actions[i]) == 1:
                button = int(actions[i]); i += 1
            if verb == "click":
                client.click(int(x), int(y), button)
            elif verb == "down":
                client.pointer(x, y, 1 << (button - 1))
            else:
                client.pointer(x, y, 0)
        elif verb == "drag":
            x1, y1, x2, y2 = actions[i + 1:i + 5]
            client.pointer(x1, y1, 0); time.sleep(0.2)
            client.pointer(x1, y1, 1); time.sleep(0.2)
            client.pointer(x2, y2, 1); time.sleep(0.2)
            client.pointer(x2, y2, 0)
            i += 5
        elif verb == "key":
            client.key(actions[i + 1]); i += 2
        elif verb == "keydown":
            client.key(actions[i + 1], True); i += 2
        elif verb == "keyup":
            client.key(actions[i + 1], False); i += 2
        elif verb == "combo":
            # e.g. combo Control_L Escape — hold the leading keys, tap the last
            names = actions[i + 1].split("+")
            for n in names[:-1]:
                client.key(n, True); time.sleep(0.08)
            client.key(names[-1]); time.sleep(0.08)
            for n in reversed(names[:-1]):
                client.key(n, False)
            i += 2
        elif verb == "text":
            client.text(actions[i + 1]); i += 2
        elif verb == "clear":
            client.clear_field(); i += 1
        elif verb == "dblclick":
            client.dblclick(int(actions[i + 1]), int(actions[i + 2])); i += 3
        elif verb == "sleep":
            time.sleep(float(actions[i + 1])); i += 2
        elif verb == "shot":
            to_png(client.framebuffer(), client.width, client.height, actions[i + 1])
            print(f"shot {actions[i + 1]}")
            i += 2
        elif verb == "cursor":
            pos = find_cursor(client.framebuffer(), client.width, client.height)
            print(f"cursor {pos[0]} {pos[1]}" if pos else "cursor none")
            i += 1
        else:
            raise SystemExit(f"unknown action {verb!r}")


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("target", help="host:port (port defaults to 5901)")
    parser.add_argument("actions", nargs="+")
    parser.add_argument("--timeout", type=float, default=25)
    parser.add_argument("--hold", type=float, default=0.6,
                        help="seconds to hold the button down; raise it for "
                             "games that poll the mouse slowly")
    parser.add_argument("--settle", type=float, default=0.7,
                        help="seconds to let the guest cursor reach the target "
                             "before pressing the button")
    parser.add_argument("--key-delay", type=float, default=0.06,
                        help="seconds between keystrokes; raise it when the "
                             "guest is busy and drops keys")
    args = parser.parse_args()

    host, _, port = args.target.partition(":")
    client = Client(host, int(port or 5901), timeout=args.timeout, key_delay=args.key_delay, settle=args.settle, hold=args.hold)
    print(f"connected: {client.name} {client.width}x{client.height}")
    run_actions(client, args.actions)


if __name__ == "__main__":
    try:
        main()
    except (RFBError, OSError) as exc:
        sys.exit(f"vnc-drive: {exc}")
