#!/usr/bin/env python3
"""Small QMP/HMP control helper for the emulator container."""

import json
import socket
import sys


QMP_SOCK = "/tmp/qemu-qmp.sock"


def qmp_cmd(command, arguments=None, timeout=30):
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sock:
        sock.settimeout(timeout)
        sock.connect(QMP_SOCK)
        sock.recv(4096)
        sock.sendall(json.dumps({"execute": "qmp_capabilities"}).encode() + b"\n")
        sock.recv(4096)
        payload = {"execute": command}
        if arguments:
            payload["arguments"] = arguments
        sock.sendall(json.dumps(payload).encode() + b"\n")
        return sock.recv(65536).decode(errors="replace")


def hmp(line):
    return qmp_cmd(
        "human-monitor-command",
        {"command-line": line},
    )


def usage():
    print(
        "Usage: qmp-control.py <command> [args...]\n"
        "Commands:\n"
        "  hmp <line>\n"
        "  info-snapshots\n"
        "  savevm <name>\n"
        "  loadvm <name>\n"
        "  delvm <name>\n"
        "  screendump <path.ppm>\n"
        "  sendkey <keys>\n"
        "  system-reset\n"
        "  system-powerdown\n"
        "  quit\n"
        "  stop\n"
        "  cont\n"
        "  query-block",
        file=sys.stderr,
    )


def main(argv):
    if len(argv) < 2:
        usage()
        return 2

    cmd = argv[1]
    if cmd == "hmp" and len(argv) >= 3:
        print(hmp(" ".join(argv[2:])))
    elif cmd == "info-snapshots":
        print(hmp("info snapshots"))
    elif cmd in {"savevm", "loadvm", "delvm"} and len(argv) == 3:
        print(hmp(f"{cmd} {argv[2]}"))
    elif cmd == "screendump" and len(argv) == 3:
        print(hmp(f"screendump {argv[2]}"))
    elif cmd == "sendkey" and len(argv) == 3:
        print(hmp(f"sendkey {argv[2]} 100"))
    elif cmd == "system-reset":
        print(qmp_cmd("system_reset"))
    elif cmd == "system-powerdown":
        print(qmp_cmd("system_powerdown"))
    elif cmd in {"quit", "stop", "cont"}:
        print(qmp_cmd(cmd))
    elif cmd == "query-block":
        print(qmp_cmd("query-block"))
    else:
        usage()
        return 2

    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
