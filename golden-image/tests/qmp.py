#!/usr/bin/env python3
"""qmp.py — tiny QMP client for the golden-image host test harness.

Usage:
  qmp.py <sock> status                 -> prints running/paused
  qmp.py <sock> hmp "<monitor cmd>"    -> runs an HMP command
  qmp.py <sock> screendump <file.ppm>  -> capture the framebuffer
"""
import json
import socket
import sys


def connect(path):
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(15)
    s.connect(path)
    f = s.makefile("rw")
    f.readline()  # greeting
    s.sendall(b'{"execute":"qmp_capabilities"}\n')
    f.readline()
    return s, f


def cmd(s, f, execute, arguments=None):
    m = {"execute": execute}
    if arguments:
        m["arguments"] = arguments
    s.sendall((json.dumps(m) + "\n").encode())
    return f.readline().strip()


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    sock, action = sys.argv[1], sys.argv[2]
    s, f = connect(sock)
    if action == "status":
        print(cmd(s, f, "query-status"))
    elif action == "hmp":
        print(cmd(s, f, "human-monitor-command", {"command-line": sys.argv[3]}))
    elif action == "screendump":
        print(cmd(s, f, "human-monitor-command", {"command-line": f"screendump {sys.argv[3]}"}))
    else:
        print(f"unknown action: {action}")
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
