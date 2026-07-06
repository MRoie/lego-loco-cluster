# Lego Loco Cluster — LAN Multiplayer Bring-up & GHCR Publish Runbook

> Purpose: reproducible procedure for getting the two Win98 emulator pods to see each
> other in a Lego Loco LAN game, and for baking + publishing the resulting images to
> GHCR. Also an honest log of the failures hit along the way so they can be recognized
> and avoided next time.
>
> Owner/registry: `ghcr.io/mroie/lego-loco-cluster/*` (GitHub: `MRoie/lego-loco-cluster`)
> Date of first full run: 2026-07-04 → 2026-07-05

---

## Quickstart (one command)

Once the network-ready emulator image exists locally (built + baked per §2),
the whole flow is wrapped by a single script:

```bash
# Cluster up → build/load images → deploy 2-instance LAN → drive both guests
# into a TCP multiplayer game → capture proof screendumps under proof/
scripts/start-lan-game.sh

# Also record the dashboard's progressive loading as video evidence:
scripts/start-lan-game.sh --record

# Reuse an existing cluster/images, deploy-and-wait only (no in-game steps):
scripts/start-lan-game.sh --skip-cluster --skip-build --skip-game
```

The in-game choreography lives in editable step files
(`scripts/lan-game-steps/{host-create,guest-join}.steps`) run by
`scripts/lan-game-steps.py` — a data-driven QMP runner (`hmp` / `loadvm` /
`sleep` / `dump`). If the guests lack a baked `mainmenu` savevm, `loadvm`
degrades gracefully and the script continues from whatever state the guests
booted into. The manual bring-up below (§1–§5) is the source of truth those
step files were recorded from.

---

## 0. TL;DR / mental model

- Each emulator pod runs **QEMU (`qemu-system-i386`, TCG)** booting a Win98 SE qcow2.
- Guest NIC is emulated **`ne2k_pci`** on MAC `52:54:00:10:00:0<idx>`, wired to a host TAP
  (`tap<idx>`) on a per-pod Linux bridge **`loco-br`** (`192.168.10.1/24`, guest gw
  `192.168.10.20<idx>`).
- Pods are stitched into one L2 segment by a **VXLAN mesh** (`vxlan<idx>`, VXLAN id 42,
  UDP 4789) enslaved to `loco-br`; peers discovered via the StatefulSet headless service.
- A tiny **DHCP server** (`mini_dhcp.py`) runs on instance-0 and hands the guest
  `192.168.10.<10+macLastByte>` (so guest-0 = `.10`, guest-1 = `.11`).
- Guest identity (computer name `LOCO-0<idx>`, workgroup, static-vs-DHCP) is injected via
  an identity floppy / registry import (`customize-win98-instance.sh`).

**The single thing that actually broke LAN play:** the Win98 guest had **no network
adapter driver installed**, so the OS never bound a TCP/IP stack to the `ne2k_pci` card.
The VXLAN mesh, bridge, TAP and DHCP were all fine — the guest simply didn't answer ARP
for its own IP. Fix = install the RTL8029(AS) driver (Win98's driver for the ne2k_pci)
from the Win98 CD.

---

## 1. Symptoms that point at this problem

Run `scripts/check-pod-network.ps1` / `scripts/check-mesh-detail.ps1`. Diagnostic ⇒ cause:

- `ip neigh ... 192.168.10.10 dev loco-br FAILED` **even from the guest's own pod** ⇒
  guest isn't answering ARP locally ⇒ NIC stack not bound (driver missing) — NOT a mesh bug.
- `nc -z <guest-ip> <port>` **times out** ⇒ no L2/L3 path (mesh/bridge problem).
- `nc -z <guest-ip> <port>` **connection refused** ⇒ network is fine, just no listener yet
  (e.g. game not in multiplayer mode). This is the *good* failure.
- `bridge fdb show br loco-br | grep 52:54` shows the guest MACs on `tap<idx>` **and** on
  the peer's `vxlan<idx>` ⇒ mesh is healthy.

---

## 2. Full procedure (fresh cluster → LAN game → GHCR)

All helper scripts live in `scripts/` and follow the pattern `name.bat` → runs
`name.ps1` → writes `name-result.txt` (the `-result.txt` files are gitignored).
`.bin/` holds `kind.exe`, `kubectl.exe`, `helm.exe`; `KUBECONFIG=.kube-config`.

### 2.1 Build & load the emulator image  (`scripts/rebuild1-emulator-image.ps1`)
1. `kind delete cluster --name loco` then `kind create cluster --name loco --wait 180s`.
2. `docker pull ghcr.io/mroie/lego-loco-cluster/win98-softgpu:latest`  (~3.3 GB base).
3. Build the network patch layer (fresh entrypoint + `mini_dhcp.py` + `qmp-control.py`):
   `docker build -f containers/qemu-softgpu/Dockerfile.patch-network -t lego-loco-emulator:lan-test containers/qemu-softgpu`
4. **Flatten** it (the base carries a qcow2 with a *backing file*, which `kind load`/`docker save`
   choke on): `docker create` → `docker export` → `docker import` →
   `lego-loco-emulator:lan-test-flat`. Keep the ~2.75 GB tar on the Windows disk
   (`G:\dev\.dockertemp`), NOT inside the Docker VM.
5. `kind load docker-image lego-loco-emulator:lan-test-flat --name loco`.

### 2.2 Build/deploy apps  (`scripts/deploy-lan-test.ps1`)
- `docker build -f backend/Dockerfile --target production -t lego-loco-backend:local .`
  (**context = repo root** — the Dockerfile does `COPY backend/. .` and `COPY utils`).
- `docker build -f frontend/Dockerfile --target production -t lego-loco-frontend:local ./frontend`
  (**context = `frontend/`**).
- `kind load docker-image lego-loco-backend:local --name loco` (and frontend).
- `kubectl create namespace loco`.
- `helm upgrade --install loco helm/loco-chart -n loco -f helm/loco-chart/values-lan-test.yaml`.
  Values pin `lego-loco-emulator:lan-test-flat`, `*-backend:local`, `*-frontend:local`,
  all `imagePullPolicy: Never`, `replicas: 2`.

### 2.3 Install the guest NIC driver  (the actual fix)
The guests boot with the ne2k card but no driver. Attach the Win98 CD and run the
Add-New-Hardware wizard:
1. Copy the ISO to the kind node: `docker cp "containers\Windows 98 Second Edition.iso" loco-control-plane:/opt/win98se.iso`.
2. Patch the StatefulSet to mount it as a CD and pass it to QEMU
   (`scripts/win98cd-patch.yaml` → adds `-drive file=/images/win98se.iso,media=cdrom,if=ide,index=2`),
   then delete the pods so they restart with the CD. (`scripts/apply-win98cd2.ps1`.)
3. Drive the guest via QMP `sendkey` + screendumps (`scripts/qmp-control.py`,
   `scripts/qmp-steps.ps1` step runner). Sequence per guest:
   - Dismiss the network-logon dialog (Enter).
   - Add New Hardware Wizard → Next → "Search for best driver" → Next →
     **untick Floppy, tick CD-ROM** → Next → it finds **Realtek RTL8029(AS) PCI Ethernet
     NIC** at `C:\WINDOWS\INF\NETRT.INF` → Next → files copy from CD → Finish → **Yes** to
     reboot.
   - After reboot, if you get *"Error 38: computer name already in use"*, two guests share
     a name. Open Network control panel → Identification, give each a unique name
     (e.g. `L1`/`L2`) in the same workgroup (`LOCO`), OK, reboot.
4. Verify (`scripts/check-net2.ps1` / `scripts/verify-net3.ps1`): DHCP `ACK`s in the
   instance-0 log, `nc -z <peer> 139` **succeeds**, `ip neigh` shows peers `REACHABLE`,
   `bridge fdb` shows both `52:54:00:...` MACs. This state **cold-boots** network-ready.

### 2.4 In-game
`loadvm mainmenu` (a QMP savevm taken at the Lego Loco main menu) jumps straight to the
menu and **skips the intro cinematic** (see failure #5). From the menu: pick the
2-figure multiplayer briefcase → create (pencil) or join (binoculars) → select **TCP** →
green check → host shows a lobby / joiner shows "SEARCHING FOR GAMES". Both guests then
appear in each other's game.

### 2.5 Bake + publish the NIC image
- Take restore points inside the qcow2 with QMP `savevm netready` (clean desktop, network
  verified) and optionally `savevm mainmenu`.
- Extract the overlay cheaply: QMP `stop` → `cp` the per-instance qcow2 aside → QMP `cont`
  → `kubectl cp` the ~360 MB overlay to `containers/qemu-softgpu/tmp-bake/overlay.qcow2`.
- **Flatten inside the docker build** (has the base + `qemu-img`, plenty of space):
  `RUN qemu-img rebase -b '' /opt/builtin-images/win98.qcow2.builtin` after copying the
  overlay over it. (Do NOT flatten inside the pod — the emptyDir is small; see failure #2.)
- Tag `ghcr.io/mroie/lego-loco-cluster/win98-softgpu:nic-net-<date>` (+ `:latest`), push.
- Also push `backend` and `frontend`:
  `docker tag ... ghcr.io/mroie/lego-loco-cluster/backend:latest && docker push ...`.

---

## 3. Failure log (what actually happened, and the fix)

1. **Wrong initial diagnosis — "VXLAN mesh broken".** Cross-pod `nc` to DirectPlay ports
   timed out and ARP FAILED, which looked like a mesh problem. Pod-level checks showed the
   guest failed ARP for *its own* IP on `loco-br`, proving the mesh was fine and the guest
   NIC stack was unbound. **Lesson:** test same-pod guest reachability first; distinguish
   `timed out` (path) from `refused`/`FAILED-ARP` (guest stack).

2. **`qemu-img rebase` inside the pod → `Read-only file system` / `Input/output error`.**
   The `/images` emptyDir couldn't absorb the ~1.9 GB flatten write. **Fix:** copy the
   small overlay out and flatten during `docker build` instead.

3. **kind node filesystem went read-only mid-run; then the whole `/var/lib/docker`.**
   Under heavy qcow2 + image I/O, the Docker Desktop WSL2 ext4 vhdx corrupted and
   remounted read-only. `touch`, `df`, even `dd`/`find` returned `Input/output error`;
   kube-apiserver died (`kubectl: EOF` / `TLS handshake timeout`); `docker tag`/`build`/
   `push` all failed `read-only file system`. **A plain Docker restart and a full PC reboot
   did NOT clear it** (fsck-on-boot didn't repair the vhdx). The in-pod NIC qcow2 (in
   emptyDir on the corrupted disk) was unrecoverable. **Fix:** factory-reset Docker's data
   disk — quit Docker, `wsl --shutdown`, `wsl --unregister docker-desktop-data`, relaunch
   Docker Desktop (recreates a clean read-write data distro; settings preserved; **all local
   images/containers are wiped**). See `scripts/reset-docker.ps1` + `scripts/start-docker.ps1`.
   **Lesson:** keep the valuable guest disk baked into an *image* pushed to GHCR, don't
   leave it only in an ephemeral emptyDir.

4. **Reading stale `-result.txt`.** Concurrent `.bat` runs writing the same result file,
   plus PowerShell `Select-Object -Last N` buffering docker build/pull output until the
   command completes, made builds look "stuck"/"failed" when they were fine. **Lesson:**
   use a unique result filename per run; don't trust an unchanging file as "hung" until you
   confirm via `docker ps` / `docker images` / `kind get clusters`.

5. **Intro cinematic freezes QEMU under TCG.** The 3D-brick intro reproducibly hangs the
   display (identical frames, VM effectively wedged). **Workaround:** never rely on getting
   through the intro live — take a `savevm` at the main menu once and `loadvm mainmenu`
   thereafter.

6. **Guest mouse via QMP `mouse_move` is relative/accelerated, not absolute.** Absolute
   coordinates don't map linearly; small paced relative moves (and a corner reset first)
   are needed to land on buttons. Prefer keyboard/`savevm` navigation where possible.

7. **Build context mistakes.** `backend/Dockerfile` needs the **repo root** as context
   (it copies `backend/.` and `utils`); building with `backend/` as context fails
   `"/backend" not found`. `frontend/Dockerfile` uses `frontend/` as context.

8. **Explorer launch quirks (automation).** Double-click sometimes registers as two single
   clicks (select only). Selecting the `.bat` and pressing **Enter** launches reliably.

---

## 4. Script index (this effort)

| Script | Purpose |
|---|---|
| `check-pod-network.ps1`, `check-mesh-detail.ps1` | Diagnose mesh vs guest-stack |
| `diag-guest-net.ps1` | QEMU cmdline, tap counters, DHCP log lines |
| `apply-win98cd2.ps1`, `win98cd-patch.yaml` | Attach Win98 CD to the emulator pods |
| `qmp-control.py`, `qmp-steps.ps1` (+ `qmp-steps.txt`) | Drive guest via QMP sendkey/mouse/screendump |
| `check-net2.ps1`, `verify-net3.ps1` | Verify DHCP + cross-pod TCP after NIC install |
| `reset-docker.ps1`, `start-docker.ps1` | Factory-reset + restart Docker Desktop (WSL2) |
| `rebuild1-emulator-image.ps1` | Fresh cluster + build/flatten/load emulator image |
| `build-push-apps.ps1`, `finalize-apps.ps1` | Build + push backend/frontend to GHCR |
| `bake-extract2.ps1` | Copy guest overlay out for baking |

---

## 5. Published images (GHCR)

- `ghcr.io/mroie/lego-loco-cluster/backend:latest` (+ dated tag)
- `ghcr.io/mroie/lego-loco-cluster/frontend:latest` (+ dated tag)
- `ghcr.io/mroie/lego-loco-cluster/win98-softgpu:latest` — SoftGPU Win98 base
- `ghcr.io/mroie/lego-loco-cluster/win98-softgpu:nic-net-<date>` — **NIC driver installed,
  cold-boots network-ready** (bake from §2.5)
- `ghcr.io/mroie/lego-loco-cluster/emulator-snapshot:netready` (+ `:20260705`, `:latest`) —
  raw flattened qcow2 disk (NIC driver installed, `netready` internal QMP snapshot preserved),
  wrapped in a `FROM scratch` image since `oras` isn't installed on this machine. Extracted from
  a single-instance Docker Desktop Kubernetes deployment (see §6 below): QMP `stop` → `cp` the
  instance qcow2 aside → QMP `cont` → `qemu-img rebase -b ''` in place (backing file was already
  present in the running pod's image, so no separate flatten container was needed) → `kubectl cp`
  out → `docker build -f Dockerfile.snapshot` → push. Digest
  `sha256:3781a47ae06030504b11919c9a0c9353d54feeb06a858418d51cd92b7dbc2a42`, image size 1.27GB.
  To get the qcow2 back out: `docker create --name tmp ghcr.io/mroie/lego-loco-cluster/emulator-snapshot:netready && docker cp tmp:/emulator-snapshot/netready.qcow2 . && docker rm tmp`.

Pull test: `docker pull ghcr.io/mroie/lego-loco-cluster/win98-softgpu:nic-net-<date>`.

---

## 6. Docker Desktop Kubernetes single-machine validation (2026-07-05, follow-up)

The `kind load docker-image` slowness (§3 item 3) turned out to compound with the same
underlying disk/AV I/O contention affecting `kind delete cluster` too (observed hanging
30+ minutes on a clean teardown). Strategy: sidestep `kind` entirely for the first
validation pass and deploy straight to **Docker Desktop's built-in Kubernetes**, which
shares the host's Docker image store directly (no load/pull step at all).

- New overlay: `helm/loco-chart/values-dd-single.yaml` (`replicas: 1`, same images as
  `values-lan-test.yaml`, `networkPolicy.enabled: false`).
- Chart bug fixed: `templates/storage-strategy.yaml` rendered
  `empty-dir-medium: ` (blank → YAML `null`) which Docker Desktop's K8s (v1.19.7) rejects
  as `unknown object type "nil" in ConfigMap.data`. Fixed by piping both `emptyDir.medium`
  and `emptyDir.sizeLimit` through `| quote`.
- Image tag gotcha: chart expects bare `lego-loco-backend:local` / `lego-loco-frontend:local`;
  only the `ghcr.io/...` tags existed locally → `ErrImageNeverPull`. Fixed with
  `docker tag ghcr.io/.../backend:latest lego-loco-backend:local` (+ frontend) and a
  `kubectl rollout restart`.
- NIC driver install repeated against this single instance (`loco-loco-emulator-0`):
  CD attached via QMP hot-insert (`hmp change ide1-cd0 /images/win98se.iso`, no restart
  needed) rather than the hostPath-node-patch method in §2.3 (Docker Desktop's node is the
  Docker Desktop VM itself, not a discrete `docker exec`-able node container like kind's).
  Wizard driven via `qmp-control.py sendkey`/`screendump`, verified visually at each step.
- Post-reboot verification (single pod, no peer to LAN-test against, so verified the same
  "guest answers for itself" symptom from §1): DHCP ACK in logs, `ip neigh`/`/proc/net/arp`
  resolved for the guest IP, `nc -z 192.168.10.10 139` **succeeded**. Confirms the NIC driver
  fix is what mattered, independent of kind vs. Docker Desktop K8s.
- Snapshot `netready` taken via QMP `savevm` (87.3 MiB), VM resumed cleanly after.
