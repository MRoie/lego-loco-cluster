#!/usr/bin/env python3
"""
Compact QMP computer-use automation for Lego Loco cluster.
Uses 'human-monitor-command' for reliable key/mouse injection.

Usage:
  python3 qmp_automate.py dismiss          # Dismiss startup dialogs
  python3 qmp_automate.py launch           # Double-click Lego Loco on desktop
  python3 qmp_automate.py host             # Host a network game
  python3 qmp_automate.py join             # Join a network game
  python3 qmp_automate.py full-host        # dismiss + launch + host (instance 0)
  python3 qmp_automate.py full-join        # dismiss + launch + join (instances 1-N)
  python3 qmp_automate.py auto             # auto-detect: host if INSTANCE_ID=0, else join
  python3 qmp_automate.py screenshot       # Take screenshot, report top colors
"""

import json
import os
import socket
import sys
import time

# --- QMP Connection (robust line-buffered protocol) ---

class QMP:
    """Robust QMP client using line-buffered reads and human-monitor-command."""

    def __init__(self, sock_path):
        self.sock_path = sock_path
        self.sock = None
        self.buf = b""

    def connect(self):
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.settimeout(10)
        self.sock.connect(self.sock_path)
        # Read greeting
        greeting = self._read_json()
        ver = greeting.get("QMP", {}).get("version", {}).get("qemu", {})
        p(f"[QMP] Connected: QEMU {ver.get('major','?')}.{ver.get('minor','?')}.{ver.get('micro','?')}")
        # Negotiate capabilities
        resp = self.cmd("qmp_capabilities")
        p("[QMP] Ready")
        return self

    def _read_json(self):
        """Read exactly one JSON object from the socket (line-delimited)."""
        while True:
            # Check if we have a complete line in buffer
            nl = self.buf.find(b"\n")
            if nl >= 0:
                line = self.buf[:nl]
                self.buf = self.buf[nl+1:]
                if line.strip():
                    try:
                        return json.loads(line)
                    except json.JSONDecodeError:
                        pass
                continue
            # Also try parsing buffer without newline (some QMP versions)
            if self.buf.strip():
                try:
                    obj = json.loads(self.buf)
                    self.buf = b""
                    return obj
                except json.JSONDecodeError:
                    pass
            # Read more
            try:
                chunk = self.sock.recv(4096)
                if not chunk:
                    return {}
                self.buf += chunk
            except socket.timeout:
                return {}

    def cmd(self, execute, arguments=None):
        """Send a QMP command and wait for the response (skipping events)."""
        msg = {"execute": execute}
        if arguments:
            msg["arguments"] = arguments
        self.sock.sendall(json.dumps(msg).encode() + b"\n")
        # Read responses, skip events
        for _ in range(20):
            resp = self._read_json()
            if "return" in resp or "error" in resp:
                return resp
            # It's an event, skip it
        return {}

    def hmp(self, command_line):
        """Execute a human monitor command (HMP) via QMP. Most reliable method."""
        return self.cmd("human-monitor-command",
                        {"command-line": command_line})

    def sendkey(self, keyname, hold_ms=100):
        """Send a key using HMP sendkey (most reliable)."""
        self.hmp(f"sendkey {keyname} {hold_ms}")

    def mouse_move_abs(self, x, y):
        """Move mouse to absolute pixel coords using HMP."""
        self.hmp(f"mouse_move {x} {y}")

    def mouse_click(self, button=0):
        """Click mouse button (0=left, 1=middle, 2=right) using HMP."""
        self.hmp(f"mouse_button {1 << button}")
        time.sleep(0.05)
        self.hmp(f"mouse_button 0")

    def screendump(self, path="/tmp/screen.ppm"):
        """Take a screenshot."""
        return self.cmd("screendump", {"filename": path})

    def close(self):
        if self.sock:
            self.sock.close()


# --- HMP key names (QEMU sendkey names, NOT scancodes) ---
# Full list: qemu-system-i386 -display none -monitor stdio; then "sendkey" tab
HMP_KEYS = [
    "esc", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0",
    "ret", "spc", "tab", "backspace",
    "shift", "shift_r", "ctrl", "alt", "caps_lock",
    "f1", "f2", "f3", "f4", "f5", "f6", "f7", "f8", "f9", "f10", "f11", "f12",
    "up", "down", "left", "right",
    "home", "end", "pgup", "pgdn", "insert", "delete",
    "a", "b", "c", "d", "e", "f", "g", "h", "i", "j",
    "k", "l", "m", "n", "o", "p", "q", "r", "s", "t",
    "u", "v", "w", "x", "y", "z",
]

# Aliases for convenience
KEY_ALIASES = {
    "enter": "ret", "return": "ret", "space": "spc",
    "lshift": "shift", "rshift": "shift_r",
    "lctrl": "ctrl", "lalt": "alt",
    "pageup": "pgup", "pagedown": "pgdn",
}


def p(msg):
    """Print with flush."""
    print(msg, flush=True)


def key(qmp, name, delay=0.3):
    """Press a named key via HMP sendkey."""
    hmp_name = KEY_ALIASES.get(name.lower(), name.lower())
    p(f"  key: {name} -> {hmp_name}")
    qmp.sendkey(hmp_name)
    time.sleep(delay)


def click(qmp, x, y, delay=0.5):
    """Click at screen coordinates (1024x768)."""
    p(f"  click: ({x}, {y})")
    qmp.mouse_move_abs(x, y)
    time.sleep(0.1)
    qmp.mouse_click(0)
    time.sleep(delay)


def dblclick(qmp, x, y, delay=1.0):
    """Double-click at screen coordinates."""
    p(f"  dblclick: ({x}, {y})")
    qmp.mouse_move_abs(x, y)
    time.sleep(0.1)
    qmp.mouse_click(0)
    time.sleep(0.15)
    qmp.mouse_click(0)
    time.sleep(delay)


# --- Automation Sequences ---

def dismiss_dialogs(qmp, rounds=5):
    """
    Dismiss Win98 startup dialogs, driver prompts, etc.
    Strategy: repeatedly press Escape, Enter, and click center.
    """
    p("[AUTO] Dismissing startup dialogs...")
    for i in range(rounds):
        p(f"  round {i+1}/{rounds}")
        key(qmp, "esc", 0.2)
        key(qmp, "enter", 0.2)
        click(qmp, 512, 384, 0.2)   # Center
        key(qmp, "esc", 0.2)
        click(qmp, 512, 450, 0.15)  # OK button area
        click(qmp, 680, 450, 0.15)  # Next button
        key(qmp, "enter", 0.3)
    # Final cleanup
    key(qmp, "esc", 0.3)
    click(qmp, 400, 300, 0.3)
    p("[AUTO] Dialogs dismissed")


def launch_lego_loco(qmp):
    """
    Launch Lego Loco from Win98 desktop.
    Strategy: double-click desktop icon, fallback to Start menu.
    """
    p("[AUTO] Launching Lego Loco...")

    # Try desktop shortcut - Win98 icons at top-left, ~75px spacing
    dblclick(qmp, 40, 40, 3)   # First icon

    # Fallback: Start → Programs → Lego Loco
    p("[AUTO] Start menu fallback...")
    click(qmp, 20, 750, 1)      # Start button
    click(qmp, 100, 680, 1)     # Programs
    click(qmp, 250, 400, 2)     # Submenu

    # Wait for game load
    p("[AUTO] Waiting for game (15s)...")
    time.sleep(15)

    # Dismiss initial game dialogs
    key(qmp, "esc", 1)
    key(qmp, "enter", 1)
    click(qmp, 512, 384, 1)
    p("[AUTO] Lego Loco should be running")


def host_game(qmp):
    """Navigate to host a multiplayer game."""
    p("[AUTO] Hosting network game...")
    click(qmp, 512, 500, 2)    # Network button
    key(qmp, "enter", 2)
    click(qmp, 512, 350, 2)    # Host option
    key(qmp, "tab", 0.5)
    key(qmp, "enter", 2)
    p("[AUTO] Hosting - waiting for lobby (10s)...")
    time.sleep(10)


def join_game(qmp):
    """Navigate to join a network game."""
    p("[AUTO] Joining network game...")
    click(qmp, 512, 500, 2)    # Network button
    key(qmp, "enter", 2)
    click(qmp, 512, 420, 2)    # Join option
    time.sleep(3)               # Discovery
    click(qmp, 512, 300, 1)    # First game
    key(qmp, "enter", 3)
    p("[AUTO] Joined game lobby")


def take_screenshot(qmp):
    """Take screenshot and analyze colors."""
    p("[AUTO] Taking screenshot...")
    qmp.screendump("/tmp/screen.ppm")
    time.sleep(0.5)

    try:
        with open("/tmp/screen.ppm", "rb") as f:
            magic = f.readline().strip()
            line = f.readline()
            while line.startswith(b"#"):
                line = f.readline()
            w, h = map(int, line.split())
            f.readline()
            data = f.read()
        p(f"  Screen: {w}x{h}, {len(data)} bytes")

        # Sample key regions
        regions = {
            "top-left(20,20)": (20, 20),
            "center(512,384)": (512, 384),
            "taskbar(512,740)": (512, 740),
            "bottom-left(20,740)": (20, 740),
        }
        for name, (x, y) in regions.items():
            off = (y * w + x) * 3
            if off + 3 <= len(data):
                r, g, b = data[off], data[off+1], data[off+2]
                label = ""
                if r > 200 and g > 200 and b > 200: label = "WHITE"
                elif r < 30 and g < 30 and b < 30: label = "BLACK"
                elif r < 30 and g > 80 and b > 80: label = "TEAL"
                elif abs(r-192) < 40 and abs(g-192) < 40 and abs(b-192) < 40: label = "GRAY"
                elif r < 30 and g < 30 and b > 100: label = "BLUE"
                else: label = "other"
                p(f"  {name}: RGB({r},{g},{b}) [{label}]")

        # Color histogram
        colors = {}
        for i in range(0, min(len(data), w*h*3), 30):
            key_c = (data[i]//64, data[i+1]//64, data[i+2]//64)
            colors[key_c] = colors.get(key_c, 0) + 1
        top = sorted(colors.items(), key=lambda x: -x[1])[:5]
        total = sum(c for _, c in top)
        p("  Top colors:")
        for (r, g, b), cnt in top:
            p(f"    ~({r*64+32},{g*64+32},{b*64+32}): {cnt*100//total}%")

    except Exception as e:
        p(f"  Screenshot analysis error: {e}")


def full_sequence(qmp, role="host"):
    """Run full automation: dismiss → launch → host/join."""
    dismiss_dialogs(qmp, rounds=5)
    time.sleep(2)
    launch_lego_loco(qmp)
    time.sleep(5)
    if role == "host":
        host_game(qmp)
    else:
        join_game(qmp)


# --- Main ---

def main():
    instance_id = os.environ.get("INSTANCE_ID", "0")
    sock_path = f"/tmp/qmp-{instance_id}.sock"

    if not os.path.exists(sock_path):
        p(f"[ERROR] QMP socket not found: {sock_path}")
        sys.exit(1)

    if len(sys.argv) < 2:
        p(__doc__)
        sys.exit(1)

    cmd = sys.argv[1].lower()
    p(f"[QMP-AUTO] Command: {cmd}, Instance: {instance_id}, Socket: {sock_path}")

    qmp = QMP(sock_path).connect()

    try:
        if cmd == "dismiss":
            dismiss_dialogs(qmp)
        elif cmd == "launch":
            launch_lego_loco(qmp)
        elif cmd == "host":
            host_game(qmp)
        elif cmd == "join":
            join_game(qmp)
        elif cmd == "full-host":
            full_sequence(qmp, "host")
        elif cmd == "full-join":
            full_sequence(qmp, "join")
        elif cmd == "auto":
            role = "host" if instance_id == "0" else "join"
            p(f"[AUTO] Auto-detected role: {role}")
            full_sequence(qmp, role)
        elif cmd == "screenshot":
            take_screenshot(qmp)
        elif cmd == "key":
            key(qmp, sys.argv[2] if len(sys.argv) > 2 else "esc")
        elif cmd == "click":
            x = int(sys.argv[2]) if len(sys.argv) > 2 else 512
            y = int(sys.argv[3]) if len(sys.argv) > 3 else 384
            click(qmp, x, y)
        elif cmd == "dblclick":
            x = int(sys.argv[2]) if len(sys.argv) > 2 else 512
            y = int(sys.argv[3]) if len(sys.argv) > 3 else 384
            dblclick(qmp, x, y)
        elif cmd == "status":
            resp = qmp.cmd("query-status")
            p(json.dumps(resp, indent=2))
        else:
            p(f"[ERROR] Unknown command: {cmd}")
            p(__doc__)
    finally:
        qmp.close()


if __name__ == "__main__":
    main()
