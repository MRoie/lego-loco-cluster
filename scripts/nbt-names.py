#!/usr/bin/env python3
"""Ask a host which NetBIOS names it has registered — an `nbtstat -A` for Linux.

    nbt-names.py 192.168.10.10 192.168.10.11

This answers a question the registry cannot: what the machine is *announcing*,
as opposed to what is written down somewhere in its configuration. Those two
diverge, and when they do, reasoning from the registry sends you the wrong way.

Concretely, on this cluster: every guest is a clone of one image, and the
Windows 98 computer name lives in two live registry keys. Setting only the
obvious one left the hive looking correct while both machines still announced
the image's baked-in name, and the second guest onto the LAN put up
"Error 38: the computer name you specified is already in use on the network".
One probe made it unambiguous —

    192.168.10.10   W5C5G7 <00> UNIQUE   LOCOLAND <00> GROUP
    192.168.10.11   LOCOLAND <00> GROUP        <- and nothing else

.11 had tried to claim the name, lost, and registered no name at all. After the
fix each guest owns its own <00> UNIQUE name.

Suffixes worth knowing: <00> workstation (UNIQUE = the computer name, GROUP =
the workgroup), <03> messenger, <20> file server. A guest with a <00> GROUP
entry but no <00> UNIQUE one has failed to register its name.

There are no arguments to configure: this sends the standard wildcard node
status request to UDP 137, which any Win9x guest with NetBIOS over TCP/IP
enabled will answer. Run it from somewhere on the guests' layer 2 — inside an
emulator pod is ideal, since the pod's bridge is on the guest subnet:

    kubectl cp scripts/nbt-names.py loco/loco-loco-emulator-0:/tmp/nbt.py -c emulator
    kubectl exec -n loco loco-loco-emulator-0 -c emulator -- python3 /tmp/nbt.py 192.168.10.10
"""

import socket
import struct
import sys

# NetBIOS "first level encoding": each byte becomes two, nibble + 'A'. The
# wildcard name "*" padded to 16 bytes with NULs asks for a node status reply.
WILDCARD = b"\x2a" + b"\x00" * 15

NBSTAT, IN = 0x21, 0x01


def encode(name):
    return b"".join(bytes([0x41 + (b >> 4), 0x41 + (b & 0x0F)]) for b in name)


def node_status(host, timeout=4.0):
    enc = encode(WILDCARD)
    query = (struct.pack("!HHHHHH", 0x4242, 0x0000, 1, 0, 0, 0)
             + bytes([len(enc)]) + enc + b"\x00"
             + struct.pack("!HH", NBSTAT, IN))

    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.settimeout(timeout)
    try:
        s.sendto(query, (host, 137))
        data, _ = s.recvfrom(4096)
    except (socket.timeout, OSError) as exc:
        return None, str(exc)
    finally:
        s.close()

    # header(12) + encoded question + terminator + type/class(4) + ttl(4) + rdlen(2)
    off = 12 + 1 + len(enc) + 1 + 4 + 4 + 2
    if off >= len(data):
        return None, "short reply"

    count = data[off]
    off += 1
    names = []
    for _ in range(count):
        if off + 18 > len(data):
            break
        raw = data[off:off + 15].decode("latin-1").rstrip()
        suffix = data[off + 15]
        flags = struct.unpack("!H", data[off + 16:off + 18])[0]
        names.append((raw, suffix, "GROUP" if flags & 0x8000 else "UNIQUE"))
        off += 18
    return names, None


def main(argv):
    if len(argv) < 2:
        print(__doc__.strip().splitlines()[2].strip(), file=sys.stderr)
        return 2

    rc = 0
    for host in argv[1:]:
        names, err = node_status(host)
        if err:
            print("%-15s  no response (%s)" % (host, err))
            rc = 1
            continue
        unique = [n for n in names if n[2] == "UNIQUE" and n[1] == 0x00]
        print("%-15s  %d name(s)%s" % (host, len(names),
              "" if unique else "   <- no <00> UNIQUE name: this host failed to register one"))
        for raw, suffix, kind in names:
            print("    %-16s <%02X>  %s" % (raw, suffix, kind))
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv))
