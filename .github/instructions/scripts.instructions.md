---
description: "Use when editing shell scripts, Python utilities, or deployment automation. Covers script conventions, image creation, bridge setup, and deployment workflows."
applyTo: "scripts/**"
---
# Scripts Guidelines

## Shell Script Conventions
- Use `#!/bin/bash` with `set -euo pipefail`
- Quote all variables: `"$var"` not `$var`
- Use `[[ ]]` for conditionals
- Log with timestamps: `echo "[$(date)] message"`
- Exit with meaningful codes

## Key Scripts
- `create_win98_image.sh` — Win98 image creation pipeline
- `snapshot_builder.py` — Snapshot management (Python)
- `setup_bridge.sh` — loco-br bridge setup
- `deploy_backend_rigorous.sh` — Full deployment with checks

## Image Creation
- Source: PCem VHD → qemu-img convert → QCOW2
- Drivers: SoftGPU, RTL8029AS, SB16
- Verify with QEMU boot test after conversion

## Bridge Setup
- Bridge: loco-br at 192.168.10.1/24
- TAP: tap0-tap8 for instances 0-8
- Requires root/NET_ADMIN capability

## Knowledge
- Document in `docs/knowledge/` under relevant domain
