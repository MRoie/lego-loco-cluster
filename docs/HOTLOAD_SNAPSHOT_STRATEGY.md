# Hot-Load Snapshot Strategy

The cluster should treat "ready to play" as a runtime state, not only as a
disk image. Use two layers:

1. QCOW2 backing chains for durable branches.
2. QEMU internal VM snapshots for fast resume into a live guest state.

## Branch Layout

Recommended branch chain:

```text
base-install
  -> lego-loco
     -> multiplayer-ready
        -> game-menu-ready
        -> lan-lobby-ready
```

`base-install` and `lego-loco` can be shared across all pods. `multiplayer-ready`
and later branches may need per-instance state if Windows has already loaded
hostname, IP address, NetBIOS, or DirectPlay state.

## Runtime Controls

The emulator entrypoint supports these variables:

```yaml
emulator:
  snapshotBranch: "game-menu-ready"
  snapshotMode: "persistent"
  snapshotReset: false
  qemuLoadVm: "game-menu"
```

Equivalent environment variables:

```text
SNAPSHOT_BRANCH=game-menu-ready
SNAPSHOT_DIR=/images/snapshots
SNAPSHOT_MODE=persistent
SNAPSHOT_RESET=false
QEMU_LOADVM=game-menu
QEMU_SAVEVM_ON_EXIT=game-menu
```

When `SNAPSHOT_BRANCH` is set, the pod uses:

```text
/images/snapshots/<branch>/base.qcow2
/images/snapshots/<branch>/win98_instance_<ordinal>.qcow2
```

Each instance writes only to its own overlay. `SNAPSHOT_RESET=true` discards the
instance overlay and recreates it from the branch parent.

## QMP Operations

Inside a running emulator pod:

```bash
qmp-control.py info-snapshots
qmp-control.py savevm game-menu
qmp-control.py loadvm game-menu
qmp-control.py screendump /tmp/screen.ppm
qmp-control.py system-reset
```

Use `savevm` only after the guest is in a known-good state. For LAN testing,
capture separate per-instance snapshots after identity and network are correct,
or capture before the game caches any host identity.

## LAN Game Target

For the Lego Loco LAN path:

1. Boot `multiplayer-ready`.
2. Confirm guest-to-guest ping and DirectPlay TCP/IP provider.
3. Launch Lego Loco.
4. Navigate entry menu: right icon -> LAN/new LAN.
5. Save `game-menu` or `lan-lobby-ready` per instance.
6. Restart with `qemuLoadVm` set to that snapshot name.

On slow/no-KVM hosts, this reduces recovery time after Win98 crashes. On KVM
hosts, it should become the default way to scale many live instances.
