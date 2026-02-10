#!/usr/bin/env python3
"""
QMP Computer-Use Agent
======================

Connects to QEMU's QMP socket to inject mouse/keyboard events directly into
Win98 guests. Exposes a lightweight HTTP REST API for automation scripts.

Endpoints:
  POST /input/<instance_id>
    Body: { "type": "key"|"mouse", "key": "a", "action": "press"|"release"|"tap" }
    Body: { "type": "mouse", "x": 100, "y": 200, "button": "left", "action": "click"|"press"|"release"|"move" }
  GET  /status/<instance_id>
  GET  /health

QMP socket path convention: /tmp/qmp-<instance_id>.sock

Usage:
  python qmp_agent.py --port 9090
  python qmp_agent.py --socket /tmp/qmp.sock --instance 0

Environment variables:
  QMP_SOCKET_DIR   — directory containing qmp-N.sock files (default: /tmp)
  QMP_AGENT_PORT   — HTTP port (default: 9090)
"""

import argparse
import json
import os
import socket
import sys
import threading
import time
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse

# ---------------------------------------------------------------------------
# QMP protocol helpers
# ---------------------------------------------------------------------------

class QMPConnection:
    """Manages a QMP (QEMU Machine Protocol) socket connection."""

    def __init__(self, socket_path, timeout=5):
        self.socket_path = socket_path
        self.timeout = timeout
        self.sock = None
        self._lock = threading.Lock()

    def connect(self):
        """Connect to QMP socket and negotiate capabilities."""
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.settimeout(self.timeout)
        self.sock.connect(self.socket_path)

        # Read greeting
        greeting = self._recv_json()
        if "QMP" not in greeting:
            raise RuntimeError(f"Unexpected QMP greeting: {greeting}")

        # Negotiate capabilities
        self._send_json({"execute": "qmp_capabilities"})
        resp = self._recv_json()
        if resp.get("return") != {}:
            raise RuntimeError(f"qmp_capabilities failed: {resp}")
        return greeting

    def disconnect(self):
        if self.sock:
            try:
                self.sock.close()
            except Exception:
                pass
            self.sock = None

    def execute(self, command, arguments=None):
        """Execute a QMP command and return the response."""
        with self._lock:
            msg = {"execute": command}
            if arguments:
                msg["arguments"] = arguments
            self._send_json(msg)
            return self._recv_json()

    def _send_json(self, obj):
        data = json.dumps(obj).encode() + b"\n"
        self.sock.sendall(data)

    def _recv_json(self):
        buf = b""
        while True:
            chunk = self.sock.recv(4096)
            if not chunk:
                raise ConnectionError("QMP socket closed")
            buf += chunk
            try:
                return json.loads(buf.decode())
            except json.JSONDecodeError:
                continue


# ---------------------------------------------------------------------------
# Input event builders (QMP input-send-event format)
# ---------------------------------------------------------------------------

# Scancode mapping for common keys (PS/2 set 1 make codes)
KEY_SCANCODES = {
    "esc": 0x01, "1": 0x02, "2": 0x03, "3": 0x04, "4": 0x05,
    "5": 0x06, "6": 0x07, "7": 0x08, "8": 0x09, "9": 0x0A,
    "0": 0x0B, "minus": 0x0C, "equal": 0x0D, "backspace": 0x0E,
    "tab": 0x0F, "q": 0x10, "w": 0x11, "e": 0x12, "r": 0x13,
    "t": 0x14, "y": 0x15, "u": 0x16, "i": 0x17, "o": 0x18,
    "p": 0x19, "bracketleft": 0x1A, "bracketright": 0x1B,
    "ret": 0x1C, "enter": 0x1C, "ctrl": 0x1D,
    "a": 0x1E, "s": 0x1F, "d": 0x20, "f": 0x21, "g": 0x22,
    "h": 0x23, "j": 0x24, "k": 0x25, "l": 0x26,
    "semicolon": 0x27, "apostrophe": 0x28, "grave": 0x29,
    "shift": 0x2A, "lshift": 0x2A, "backslash": 0x2B,
    "z": 0x2C, "x": 0x2D, "c": 0x2E, "v": 0x2F, "b": 0x30,
    "n": 0x31, "m": 0x32, "comma": 0x33, "dot": 0x34,
    "slash": 0x35, "rshift": 0x36, "alt": 0x38, "lalt": 0x38,
    "space": 0x39, "capslock": 0x3A,
    "f1": 0x3B, "f2": 0x3C, "f3": 0x3D, "f4": 0x3E,
    "f5": 0x3F, "f6": 0x40, "f7": 0x41, "f8": 0x42,
    "f9": 0x43, "f10": 0x44, "f11": 0x57, "f12": 0x58,
    "up": 0x48, "down": 0x50, "left": 0x4B, "right": 0x4D,
    "insert": 0x52, "delete": 0x53, "home": 0x47, "end": 0x4F,
    "pageup": 0x49, "pagedown": 0x51,
}


def make_key_event(key, down=True):
    """Build a QMP input-send-event for a keyboard key."""
    scancode = KEY_SCANCODES.get(key.lower())
    if scancode is None:
        # Try as raw scancode number
        try:
            scancode = int(key, 0)
        except (ValueError, TypeError):
            raise ValueError(f"Unknown key: {key}")

    return {
        "type": "key",
        "data": {
            "down": down,
            "key": {
                "type": "number",
                "data": scancode
            }
        }
    }


def make_mouse_move_event(x, y):
    """Build a QMP input-send-event for absolute mouse movement."""
    # Scale to QEMU absolute coordinates (0-32767)
    # Assumes 1024x768 display
    abs_x = int((x / 1024) * 32767)
    abs_y = int((y / 768) * 32767)
    return [
        {"type": "abs", "data": {"axis": "x", "value": abs_x}},
        {"type": "abs", "data": {"axis": "y", "value": abs_y}},
    ]


def make_mouse_button_event(button="left", down=True):
    """Build a QMP input-send-event for a mouse button."""
    # QMP expects InputButton enum string, not integer
    btn_map = {"left": "left", "middle": "middle", "right": "right"}
    btn = btn_map.get(button, "left")
    return {
        "type": "btn",
        "data": {
            "down": down,
            "button": btn
        }
    }


# ---------------------------------------------------------------------------
# QMP agent — manages connections to multiple instances
# ---------------------------------------------------------------------------

class QMPAgent:
    """Manages QMP connections to multiple QEMU instances."""

    def __init__(self, socket_dir="/tmp"):
        self.socket_dir = socket_dir
        self.connections = {}
        self._lock = threading.Lock()

    def get_connection(self, instance_id):
        """Get or create a QMP connection for an instance."""
        with self._lock:
            if instance_id in self.connections:
                return self.connections[instance_id]

            sock_path = os.path.join(self.socket_dir, f"qmp-{instance_id}.sock")
            if not os.path.exists(sock_path):
                # Try alternative naming
                sock_path = os.path.join(self.socket_dir, f"qmp.sock")
                if not os.path.exists(sock_path):
                    raise FileNotFoundError(
                        f"QMP socket not found: {self.socket_dir}/qmp-{instance_id}.sock")

            conn = QMPConnection(sock_path)
            conn.connect()
            self.connections[instance_id] = conn
            return conn

    def send_key(self, instance_id, key, action="tap"):
        """Send a keyboard event to a QEMU instance."""
        conn = self.get_connection(instance_id)

        if action == "tap":
            # Press and release
            events = [make_key_event(key, down=True), make_key_event(key, down=False)]
            for ev in events:
                conn.execute("input-send-event", {"events": [ev]})
                time.sleep(0.05)
        elif action == "press":
            conn.execute("input-send-event", {"events": [make_key_event(key, down=True)]})
        elif action == "release":
            conn.execute("input-send-event", {"events": [make_key_event(key, down=False)]})

        return {"ok": True, "key": key, "action": action}

    def send_mouse(self, instance_id, x=None, y=None, button=None, action="click"):
        """Send a mouse event to a QEMU instance."""
        conn = self.get_connection(instance_id)

        if x is not None and y is not None:
            move_events = make_mouse_move_event(x, y)
            conn.execute("input-send-event", {"events": move_events})
            time.sleep(0.02)

        if button and action in ("click", "press"):
            conn.execute("input-send-event",
                         {"events": [make_mouse_button_event(button, down=True)]})
            if action == "click":
                time.sleep(0.05)
                conn.execute("input-send-event",
                             {"events": [make_mouse_button_event(button, down=False)]})
        elif button and action == "release":
            conn.execute("input-send-event",
                         {"events": [make_mouse_button_event(button, down=False)]})

        return {"ok": True, "x": x, "y": y, "button": button, "action": action}

    def query_status(self, instance_id):
        """Query QEMU status for an instance."""
        conn = self.get_connection(instance_id)
        status = conn.execute("query-status")
        return status.get("return", status)

    def close_all(self):
        with self._lock:
            for conn in self.connections.values():
                conn.disconnect()
            self.connections.clear()


# ---------------------------------------------------------------------------
# HTTP REST API server
# ---------------------------------------------------------------------------

agent = None  # Global agent instance


class QMPHandler(BaseHTTPRequestHandler):
    """HTTP handler for the QMP agent REST API."""

    def log_message(self, format, *args):
        pass  # Suppress default logging

    def _send_json_response(self, data, status=200):
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps(data).encode())

    def do_GET(self):
        parsed = urlparse(self.path)
        parts = parsed.path.strip("/").split("/")

        if parts[0] == "health":
            instances = list(agent.connections.keys()) if agent else []
            self._send_json_response({
                "status": "ok",
                "connected_instances": instances,
                "socket_dir": agent.socket_dir if agent else "",
            })
            return

        if parts[0] == "status" and len(parts) >= 2:
            instance_id = parts[1]
            try:
                status = agent.query_status(instance_id)
                self._send_json_response(status)
            except Exception as e:
                self._send_json_response({"error": str(e)}, 500)
            return

        self._send_json_response({"error": "not found"}, 404)

    def do_POST(self):
        parsed = urlparse(self.path)
        parts = parsed.path.strip("/").split("/")

        if parts[0] == "input" and len(parts) >= 2:
            instance_id = parts[1]
            content_length = int(self.headers.get("Content-Length", 0))
            body = json.loads(self.rfile.read(content_length)) if content_length else {}

            try:
                evt_type = body.get("type", "key")
                if evt_type == "key":
                    key = body.get("key", "space")
                    action = body.get("action", "tap")
                    result = agent.send_key(instance_id, key, action)
                elif evt_type == "mouse":
                    result = agent.send_mouse(
                        instance_id,
                        x=body.get("x"),
                        y=body.get("y"),
                        button=body.get("button"),
                        action=body.get("action", "click"),
                    )
                else:
                    result = {"error": f"unknown event type: {evt_type}"}

                self._send_json_response(result)
            except Exception as e:
                self._send_json_response({"error": str(e)}, 500)
            return

        self._send_json_response({"error": "not found"}, 404)


def main():
    global agent

    parser = argparse.ArgumentParser(description="QMP Computer-Use Agent")
    parser.add_argument("--port", type=int, default=int(os.environ.get("QMP_AGENT_PORT", "9090")),
                        help="HTTP server port")
    parser.add_argument("--socket-dir", default=os.environ.get("QMP_SOCKET_DIR", "/tmp"),
                        help="Directory containing QMP sockets")
    args = parser.parse_args()

    agent = QMPAgent(socket_dir=args.socket_dir)

    print(f"QMP Agent starting on port {args.port}")
    print(f"Socket directory: {args.socket_dir}")

    server = HTTPServer(("0.0.0.0", args.port), QMPHandler)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        agent.close_all()
        server.server_close()


if __name__ == "__main__":
    main()
