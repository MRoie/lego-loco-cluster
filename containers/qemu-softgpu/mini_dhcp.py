#!/usr/bin/env python3
"""Tiny DHCP server for the Win98 guest L2 network."""
import os
import socket
import struct
import sys
import time

LISTEN_IF = sys.argv[1] if len(sys.argv) > 1 else "loco-br"
SERVER_IP = os.environ.get("DHCP_SERVER_IP", os.environ.get("BRIDGE_IP", "192.168.10.200"))
NETMASK = os.environ.get("GUEST_NETMASK", "255.255.255.0")
LEASE_TIME = int(os.environ.get("DHCP_LEASE_TIME", "86400"))


def mac_to_ip(mac_bytes):
    return f"192.168.10.{10 + mac_bytes[5]}"


def ip_to_bytes(ip):
    return socket.inet_aton(ip)


def build_reply(xid, yiaddr, mac, msg_type):
    reply = bytearray(300)
    reply[0] = 2  # BOOTREPLY
    reply[1] = 1  # Ethernet
    reply[2] = 6  # MAC length
    struct.pack_into(">I", reply, 4, xid)
    struct.pack_into(">H", reply, 10, 0x8000)
    reply[16:20] = ip_to_bytes(yiaddr)
    reply[20:24] = ip_to_bytes(SERVER_IP)
    reply[28:34] = mac
    reply[236:240] = b"\x63\x82\x53\x63"

    opts = bytearray()
    opts += bytes([53, 1, msg_type])
    opts += bytes([54, 4]) + ip_to_bytes(SERVER_IP)
    opts += bytes([51, 4]) + struct.pack(">I", LEASE_TIME)
    opts += bytes([1, 4]) + ip_to_bytes(NETMASK)
    opts += bytes([3, 4]) + ip_to_bytes(SERVER_IP)
    opts += bytes([6, 4]) + ip_to_bytes(SERVER_IP)
    opts += bytes([255])
    reply[240 : 240 + len(opts)] = opts
    return bytes(reply[: 240 + len(opts)])


def dhcp_message_type(data):
    if len(data) < 240 or data[236:240] != b"\x63\x82\x53\x63":
        return None
    i = 240
    while i < len(data):
        opt = data[i]
        if opt == 255:
            return None
        if opt == 0:
            i += 1
            continue
        if i + 1 >= len(data):
            return None
        length = data[i + 1]
        if opt == 53 and length == 1:
            return data[i + 2]
        i += 2 + length
    return None


def main():
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    sock.setsockopt(socket.SOL_SOCKET, 25, (LISTEN_IF + "\0").encode())
    sock.bind(("0.0.0.0", 67))
    print(f"DHCP server listening on {LISTEN_IF}; server={SERVER_IP}", flush=True)

    while True:
        try:
            data, _ = sock.recvfrom(1500)
            if len(data) < 240 or data[0] != 1:
                continue
            msg_type = dhcp_message_type(data)
            if msg_type not in (1, 3):
                continue
            xid = struct.unpack(">I", data[4:8])[0]
            mac = data[28:34]
            mac_str = ":".join(f"{b:02x}" for b in mac)
            yiaddr = mac_to_ip(mac)
            reply_type = 2 if msg_type == 1 else 5
            action = "OFFER" if reply_type == 2 else "ACK"
            print(f"DHCP {action} {yiaddr} to {mac_str}", flush=True)
            sock.sendto(build_reply(xid, yiaddr, mac, reply_type), ("255.255.255.255", 68))
        except Exception as exc:
            print(f"DHCP error: {exc}", flush=True)
            time.sleep(1)


if __name__ == "__main__":
    main()
