# Emulator Storage Strategy & Deployment Options

## Overview
The Lego Loco Cluster emulator (`qemu-loco`) requires a Windows 98 disk image (`win98.qcow2`). The storage strategy balances between **persistence** (saving game state) and **portability** (ease of deployment).

## Current Architecture

### 1. Storage Volumes
- **HostPath (Minikube Default)**: mapped via `persistent-volume-claim.yaml` and `persistent-volume.yaml`.
  - Path: `/tmp/win98-disk` on the host node.
  - Persistent: Yes, survives pod restarts and finding.
- **EmptyDir**:
  - Path: Ephemeral volume.
  - Persistent: No, lost on pod deletion.

### 2. Initialization Flow
The `init-disk-image` container in `emulator-statefulset.yaml` is responsible for populating the disk volume **only if** `diskPVC` is defined.
- **Logic**:
  1. Checks if `/images/win98.qcow2` exists in the volume. If yes, exits (idempotent).
  2. If no, attempts to copy from `/opt/builtin-images/win98.qcow2.builtin` (expected specifically in the Docker image).
  3. Fails if neither exists.

### 3. Runtime Flow (`entrypoint.sh`)
The main emulator container has its own logic based on `USE_PREBUILT_SNAPSHOT`:
- **If `true`**: Attempts to download a snapshot from GHCR (`ghcr.io/mroie/qemu-snapshots`).
- **If `false`**: Expects a valid base image at `DISK` path to create a COW snapshot on top of.

## storage Matrix & Testable Options

We propose adding these explicitly configured modes to `values.yaml`.

### Option A: Fully Persistent (Local Dev Requirement)
**Best for**: Core development where you have the `win98.qcow2` file.
**Configuration**:
```yaml
emulator:
  diskPVC: "win98-disk"           # Use Persistent Volume
  usePrebuiltSnapshot: false      # Don't download, use local
```
**Prerequisite**: The `qemu-loco` docker image **MUST** contain `/opt/builtin-images/win98.qcow2.builtin`.
- *Issue*: Current `deployment_backend_rigorous.sh` does not enforce checking for this file before build.

### Option B: Persistent + Cloud Snapshot (Hybrid)
**Best for**: New developers checking out the repo without the private QCOW2 file.
**Configuration**:
```yaml
emulator:
  diskPVC: "win98-disk"           # Use Persistent Volume
  usePrebuiltSnapshot: true       # Download from GHCR
```
**Current Limitation**: The `init-disk-image` container currently *blocks* startup if the builtin image is missing, even if we intend to download it later.
- *Fix Needed*: Update `init-disk-image` to be permissive or support downloading.

### Option C: Ephemeral / Cloud Mode
**Best for**: CI/CD or quick verification without persistence.
**Configuration**:
```yaml
emulator:
  diskPVC: ""                     # Disable PVC (uses EmptyDir)
  usePrebuiltSnapshot: true       # Download from GHCR
```
**Result**:
- `init-disk-image` container is SKIPPED.
- Main container starts with empty `emptyDir` at `/images`.
- `entrypoint.sh` downloads snapshot to `/tmp/` (or `/images` if configured) and runs.
- **Outcome**: Working emulator, but data lost on restart.

## Recommended Changes
1.  **Refine `values.yaml`**: Add comments clearly outlining these 3 modes.
2.  **Fix `init-disk-image`**: Update `emulator-statefulset.yaml` to allow skipping the "builtin check" if strictly relying on main container download, OR implement download logic in init container.

