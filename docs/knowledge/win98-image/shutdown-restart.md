# Windows 98 Shutdown & Restart Procedures

**Date**: 2026-03-27
**Author**: @win98-lead
**Task**: W6
**Status**: finding

## Summary

Safe methods for stopping, restarting, and recovering Windows 98 guest instances running inside QEMU pods. Incorrect shutdown can corrupt the QCOW2 disk image and break snapshot chains. Always prefer graceful methods over hard termination.

---

## Method Reference

| Method | Graceful? | Data Safe? | Use When |
|--------|-----------|-----------|----------|
| Guest shutdown (Start → Shut Down) | Yes | Yes | Normal shutdown |
| QEMU `system_powerdown` | Yes | Yes | Automated graceful shutdown |
| QEMU `savevm` + `quit` | Yes | Yes | Shutdown with snapshot |
| QEMU `system_reset` | No | **No** | Guest is frozen, need reboot |
| QEMU `quit` (without save) | No | **No** | Emergency only |
| `sendkey ctrl-alt-delete` | Partial | Partial | Guest unresponsive to mouse/kb |
| `kubectl delete pod` | No | **No** | Pod-level restart via StatefulSet |
| Snapshot revert (`loadvm`) | N/A | Yes (to snapshot) | Roll back to known-good state |
| Safe Mode (F8) | N/A | Yes | Driver/config debugging |

---

## 1. Graceful Guest Shutdown

The safest method. Windows 98 flushes disk buffers and writes registry hive.

### Via Guest Desktop
1. Click **Start** button
2. Click **Shut Down...**
3. Select **"Shut down the computer"**
4. Click **OK**
5. Wait for "It's now safe to turn off your computer" screen
6. QEMU will either halt or power off automatically (depending on APM/ACPI config)

### Via QEMU Monitor (recommended for automation)
```
system_powerdown
```
This sends an ACPI power button event to the guest. Windows 98 responds by initiating a clean shutdown sequence — equivalent to pressing the power button on a real PC.

**Note**: Windows 98 requires APM support for `system_powerdown` to trigger shutdown. QEMU's default i440FX machine type includes APM. If the guest shows "It's now safe to turn off your computer" but doesn't power off, APM may not be fully configured — use `quit` after the message appears.

**Timeout**: Allow 15–30 seconds for Win98 to complete shutdown. If QEMU hasn't exited after 30s, the guest may be stalled.

---

## 2. Snapshot Save + Quit

Best method when you want to preserve exact guest state for later resume.

### Via QEMU Monitor
```
# Save current state to a named snapshot
savevm my-checkpoint

# Then quit QEMU cleanly
quit
```

### Restore later
```
# Start QEMU with the same disk image, then in monitor:
loadvm my-checkpoint
```

The guest resumes exactly where it left off — open windows, running processes, network connections (network will need re-negotiation but TCP/IP stack state is preserved).

---

## 3. System Reset (Hard Reboot)

Equivalent to pressing the reset button on a physical PC. **Does not flush disk buffers.** Use only when the guest is frozen.

### Via QEMU Monitor
```
system_reset
```

The guest reboots immediately. Windows 98 will run ScanDisk on the next boot to check for filesystem corruption.

**Risk**: Open files may be corrupted. Registry hive may be inconsistent. If corruption occurs, revert to the last good snapshot instead of continuing.

---

## 4. Emergency: Ctrl-Alt-Delete

When the guest is unresponsive to mouse/keyboard input but QEMU is still running.

### Via QEMU Monitor
```
sendkey ctrl-alt-delete
```

This injects the key combination into the guest. Windows 98 responds by:
- If at desktop: shows the Close Program dialog (task manager equivalent)
- If at login: restarts the computer
- If frozen: may have no effect (escalate to `system_reset`)

### Via VNC
Press `Ctrl+Alt+Delete` through the VNC client. Most VNC clients have a dedicated button for this to avoid triggering it on the host.

---

## 5. Safe Mode Boot

For debugging driver issues, network configuration problems, or a guest that crashes during normal boot.

### Procedure
1. Reset or restart the guest (via `system_reset` or normal reboot)
2. **Immediately** hold `F8` during the BIOS POST screen (before "Starting Windows 98")
3. The Windows 98 Startup Menu appears:
   ```
   1. Normal
   2. Logged (\BOOTLOG.TXT)
   3. Safe mode
   4. Step-by-step confirmation
   5. Command prompt only
   6. Safe mode command prompt only
   ```
4. Select option **3** for Safe Mode
5. Windows boots with minimal drivers (VGA, no network, no sound)

### Injecting F8 via QEMU Monitor
```
sendkey f8
```
**Timing is critical**: Send immediately after `system_reset`, repeatedly if needed. A small script can help:

```bash
# In entrypoint or via QMP
echo "system_reset" | socat - UNIX:/tmp/qemu-monitor.sock
sleep 2
for i in $(seq 1 5); do
  echo "sendkey f8" | socat - UNIX:/tmp/qemu-monitor.sock
  sleep 0.3
done
```

### Safe Mode Use Cases
- Remove a bad driver that causes boot loop
- Fix network settings (IP conflict, bad TCP/IP config)
- Run `regedit` to fix registry corruption
- Run `scanreg /restore` to revert to a previous registry backup

---

## 6. Snapshot Revert

Roll back to a known-good state, discarding all changes since the snapshot was taken.

### Via QEMU Monitor
```
loadvm base-install          # Revert to clean Win98 + drivers
loadvm lego-loco             # Revert to clean game install
loadvm multiplayer-ready     # Revert to configured network state
```

### When to Use
- Guest is corrupted beyond easy repair
- Testing requires a clean starting state
- After a failed driver or software install
- After a multiplayer test session (revert to pre-test state)

### Important Notes
- `loadvm` is **instant** — the guest resumes from the snapshot state
- All changes since the snapshot are **permanently lost**
- RAM state is included in the snapshot — running processes resume
- Network connections will be stale (TCP sockets from snapshot time are invalid)
- Clock will jump — Win98 may show incorrect time until NTP or manual correction

See [Snapshot Variant Matrix](snapshot-variants.md) for available snapshot names and contents.

---

## 7. Pod Restart via Kubernetes

Last resort. Terminates the QEMU process immediately without any guest-side cleanup.

### Commands
```bash
# Delete the specific pod (StatefulSet will recreate it)
kubectl delete pod loco-emulator-N -n loco

# Force delete (if pod is stuck in Terminating)
kubectl delete pod loco-emulator-N -n loco --grace-period=0 --force
```

### What Happens
1. Kubernetes sends SIGTERM to the container
2. Entrypoint script should trap SIGTERM and send `system_powerdown` to QEMU (if implemented)
3. After grace period (default 30s), Kubernetes sends SIGKILL
4. StatefulSet controller creates a new pod with the same ordinal index
5. New pod starts QEMU with the same PersistentVolume and disk image
6. Guest boots from disk (not from snapshot unless entrypoint runs `loadvm`)

### Recommended: SIGTERM Handler in Entrypoint
```bash
cleanup() {
  echo "system_powerdown" | socat - UNIX:/tmp/qemu-monitor.sock
  sleep 15
  echo "quit" | socat - UNIX:/tmp/qemu-monitor.sock
}
trap cleanup SIGTERM
```

This gives the guest a chance to shut down gracefully before the container is killed.

---

## Decision Matrix

```
Is the guest responding to input?
├── Yes → Use Guest Shutdown (Method 1) or Snapshot Save + Quit (Method 2)
├── No, but QEMU monitor works
│   ├── Need to debug? → sendkey ctrl-alt-delete (Method 4) or Safe Mode (Method 5)
│   ├── Need clean state? → Snapshot Revert (Method 6)
│   └── Just need reboot? → system_reset (Method 3)
└── No, QEMU is also frozen → kubectl delete pod (Method 7)
```

---

## References

- [Snapshot Variant Matrix](snapshot-variants.md) — snapshot names and chain
- [Instance Identity Spec](../lan-networking/instance-identity-spec.md) — per-instance pod naming
- QEMU Monitor documentation: https://www.qemu.org/docs/master/system/monitor.html
