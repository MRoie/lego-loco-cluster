---
name: win98-guest-forensics
description: Inspect and change a running Windows 98 guest inside the PCem emulator pods — read its registry, drive its GUI over VNC, edit files on its disk, and see what it is actually doing on the LAN. Use when a guest misbehaves, a setting will not take effect, the LAN or DHCP is not working, or something needs automating inside the guest.
---

# Windows 98 guest forensics

The emulator pods run a real Windows 98 SE inside PCem. It has no agent, no SSH,
no shared filesystem — the only ways in are its screen, its disk, and its
network. Every diagnostic below exists because a question could not be answered
any other way.

**The governing rule: distinguish what is configured from what is happening.**
Nearly every long-running problem in this repo has been a case of the two
diverging while looking identical from outside. The registry said the computer
name was set; the machine announced a different one. The bridge and tap looked
healthy to `ip link`; not a single frame had ever crossed them. A `.REG` file was
verifiably on the disk in the right place; nothing had ever read it. When you
find yourself reasoning from configuration, stop and go measure the behaviour.

## Reading the guest's disk

mtools reads the VHD in place, no loop mount, while the guest is running. The
`mtoolsrc` the entrypoint writes already has the partition offset:

```bash
kubectl exec -n loco loco-loco-emulator-0 -c emulator -- sh -c '
  export MTOOLSRC=/run/pcem/mtoolsrc MTOOLS_SKIP_CHECK=1
  mdir c:/WINDOWS
  mtype c:/AUTOEXEC.BAT
  mcopy -o c:/WINDOWS/SYSTEM.DAT /tmp/SYSTEM.DAT'
```

`MTOOLS_SKIP_CHECK=1` is required — without it mtools refuses this disk outright
with "Big disks not supported on this architecture".

Writes land immediately but the guest will not notice: Windows has its own view
of the filesystem in memory. Anything you write takes effect on the next boot.

## Reading the guest's registry

`scripts/win9x-hive-dump.py`. Win9x uses the CREG format; hivex and chntpw are
both NT-only, so nothing else on Linux reads these files.

```bash
win9x-hive-dump.py SYSTEM.DAT                        # every live key and value
win9x-hive-dump.py SYSTEM.DAT --find LOCO-01         # which key holds this string
win9x-hive-dump.py SYSTEM.DAT --key 'System\CurrentControlSet\Services\VxD\VNETSUP'
win9x-hive-dump.py a/SYSTEM.DAT --diff b/SYSTEM.DAT  # what differs between two guests
```

`--find` marks each hit LIVE or FREE. **Never grep a hive directly.** REGEDIT
rewrites a key into a new record and orphans the old one, whose bytes stay in the
file — so a grep finds names that Windows has not read in months, and the dead
copy looks exactly like a bug in whatever wrote the new one.

`--diff` is the fastest way to find a per-instance setting that silently failed
to apply: two guests cloned from one image should differ only in what is
genuinely per-instance, so anything identical that ought to be unique stands out.

## Changing the guest's registry

Write a `REGEDIT4` file to the disk and import it from `AUTOEXEC.BAT` in real
mode — see `inject_guest_identity()` in `containers/pcem/entrypoint.sh`:

```
C:\WINDOWS\REGEDIT.EXE /L:C:\WINDOWS\SYSTEM.DAT /R:C:\WINDOWS\USER.DAT C:\LOCOID.REG
```

At `AUTOEXEC` time Windows has not loaded, so the hives are not in use and the
merge lands before anything reads them.

**Do not use the StartUp folder for anything that Windows reads at boot.** It
runs at the end of logon, so a computer name set there could only take effect on
the *following* boot even on a perfect run. This cost a lot of time.

Always drop a marker file (`ECHO ok > C:\SOMETHING.LOG`) from any script you add.
"The script did not run" and "the script ran and the setting did not stick" look
identical from outside, and telling them apart is most of the debugging.

## Driving the guest's GUI

`scripts/vnc-drive.py` speaks RFB directly. Inside a pod, VNC is on
`127.0.0.1:5901`:

```bash
kubectl cp scripts/vnc-drive.py loco/loco-loco-emulator-0:/tmp/vd.py -c emulator
kubectl exec -n loco loco-loco-emulator-0 -c emulator -- python3 /tmp/vd.py 127.0.0.1:5901 \
    move 512 384 sleep 1 shot /tmp/s.png
kubectl cp loco/loco-loco-emulator-0:/tmp/s.png ./s.png -c emulator   # then Read it
```

Actions: `move`/`click`/`dblclick`/`down`/`up`/`drag`/`key`/`keydown`/`keyup`/
`combo`/`text`/`sleep`/`shot`. Options: `--settle` (cursor travel time before a
click), `--hold` (button hold; LOCO needs ~1.0s), `--key-delay`.

Coordinates are in the **1024x768 framebuffer**, and the guest desktop is
800x600 stretched to fill it — PCem scales, so framebuffer coordinates are not
guest pixels.

Known limits, so you do not rediscover them:

- **Double-clicking a desktop icon does not open it.** Two clicks land outside
  Windows' double-click time even at an 0.08s hold, and click-then-Enter does not
  work either. The pointer is provably landing on target; this is the launch
  path, not the input path. Launch programs from `WIN.INI`'s `[windows] run=`
  instead — it takes a space-separated list of *programs*, no arguments, so pass
  a bare 8.3 path.
- **The pointer model is open-loop.** Nothing can observe where the guest cursor
  actually is, so errors accumulate. Parking against a screen edge re-syncs it.
- Before clicking anywhere, take a screenshot and look. A modal dialog you did
  not expect will absorb the click, and on a Close Program dialog that can mean
  End Task or Shut Down.

## Seeing what the guest does on the network

`scripts/nbt-names.py` asks a host which NetBIOS names it has **registered** —
what it announces, not what its registry says:

```bash
kubectl exec -n loco loco-loco-emulator-0 -c emulator -- python3 /tmp/nbt.py 192.168.10.10
```

A guest with a `<00> GROUP` entry but no `<00> UNIQUE` one failed to register its
name — that is the Error 38 signature.

There is no `tcpdump` or `ping` in the pods. Write a small `python3` AF_PACKET
(`ETH_P_ALL`) sniffer or raw-ICMP prober and `kubectl cp` it in; `CAP_NET_ADMIN`
is available. This is the established technique here and it works.

Other checks worth knowing:

```bash
cat /run/pcem/dhcp.log                    # dnsmasq with --log-dhcp, every packet
cat /var/lib/misc/dnsmasq.leases          # empty means no lease ever completed
cat /sys/class/net/loco0/carrier          # 0 = nothing reaches the guest, ever
bridge fdb show dev vxlan42 self          # needs an all-zeros entry per peer
ip -s -br link show vxlan42               # tx_packets 0 + rising tx_dropped = no FDB
ethtool -k loco0br | grep tx-checksumming # must be off, see below
```

Three network traps, all of which presented as "the LAN looks fine and carries
nothing", and all of which are fixed in `entrypoint.sh` — recognise them if they
recur:

1. **A tap has no carrier** unless a process holds its `/dev/net/tun` fd. PCem's
   PCap backend attaches with libpcap and never opens it. Use a veth pair.
2. **The VXLAN mesh loop** must survive a peer that does not resolve yet;
   `getent hosts` exits 2 on NXDOMAIN, and under `set -euo pipefail` that killed
   the backgrounded loop on its first pass.
3. **TX checksum offload** leaves locally generated DHCP replies with an
   incomplete UDP checksum. A kernel peer would not care; Windows 98 checksums in
   software and drops them silently. The tell is that the guest's own packets
   arrive fine and it answers ARP — only checksummed inbound L4 dies.

## Health and config of the emulator itself

```bash
curl -s http://<pod>:8080/health          # ready, speed, guest_network.{ip,carrier}
cat /run/pcem/pcem.log                    # PCem stdout; PCEM_VNC_MOUSE_DEBUG traces here
cat /pcem/pcem.cfg                        # the rendered machine config
```

`containers/pcem/README.md` documents every environment variable and carries the
longer war stories.
