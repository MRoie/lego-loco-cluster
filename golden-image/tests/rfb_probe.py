#!/usr/bin/env python3
"""rfb_probe.py — verify a VNC/RFB endpoint accepts a handshake.

Does the RFB 3.x version handshake and reads the security types, without a
password (enough to prove the port speaks RFB and the server is alive). Exits
0 on a valid handshake, non-zero otherwise.

  rfb_probe.py [host] [port]   (default 127.0.0.1 5901)
"""
import socket
import sys


def main():
    host = sys.argv[1] if len(sys.argv) > 1 else "127.0.0.1"
    port = int(sys.argv[2]) if len(sys.argv) > 2 else 5901
    try:
        s = socket.create_connection((host, port), timeout=10)
    except OSError as e:
        print(f"RFB connect failed: {e}")
        return 1

    banner = s.recv(12)
    if not banner.startswith(b"RFB "):
        print(f"not an RFB server (banner={banner!r})")
        s.close()
        return 1
    print(f"RFB banner: {banner.decode(errors='replace').strip()}")

    # Reply with the same protocol version to advance the handshake.
    s.sendall(banner)
    sec = s.recv(1)
    if not sec:
        print("no security types returned")
        s.close()
        return 1
    n = sec[0]
    types = s.recv(n) if n else b""
    print(f"security types: {list(types)}")
    print("RFB handshake OK")
    s.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
