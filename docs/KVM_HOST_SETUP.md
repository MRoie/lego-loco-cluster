# KVM Host Setup

This cluster can run without KVM, but smooth Lego Loco instances require KVM.
The minimum proof is that the emulator pod can see `/dev/kvm`.

## Current Host Checks

Windows PowerShell:

```powershell
Get-CimInstance Win32_Processor |
  Select-Object Name,VirtualizationFirmwareEnabled,
    VMMonitorModeExtensions,SecondLevelAddressTranslationExtensions
```

Linux or WSL:

```bash
grep -E -m1 'vmx|svm' /proc/cpuinfo
ls -l /dev/kvm
ls -ld /dev/dri
```

Kind node:

```bash
docker exec loco-control-plane sh -lc "grep -E -m1 'vmx|svm' /proc/cpuinfo || true"
docker exec loco-control-plane sh -lc "ls -l /dev/kvm /dev/dri 2>/dev/null || true"
```

If the kind node cannot see `/dev/kvm`, setting `emulator.kvm.enabled=true`
will not help; the pod can only mount devices that exist in the node container.

## Firmware

Enable these in BIOS/UEFI:

```text
Intel Virtualization Technology / VT-x / VMX
Intel VT-d / IOMMU
```

Save settings and fully power-cycle the machine. After boot, rerun the checks
above.

## Linux Bare-Metal Path

```bash
sudo apt-get update
sudo apt-get install -y qemu-kvm cpu-checker
kvm-ok
sudo usermod -aG kvm "$USER"
```

Log out and back in after adding the user to the `kvm` group.

Create kind with device mounts:

```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  extraMounts:
  - hostPath: /dev/kvm
    containerPath: /dev/kvm
  - hostPath: /dev/dri
    containerPath: /dev/dri
```

Then deploy:

```bash
helm upgrade --install loco helm/loco-chart -n loco \
  --set emulator.kvm.enabled=true \
  --set emulator.dri.enabled=true \
  --set-string emulator.nodeSelector.loco\\.dev/kvm=true \
  --set-string emulator.nodeSelector.loco\\.dev/gpu-dri=true
```

Label suitable nodes in mixed clusters:

```bash
kubectl label node <node> loco.dev/kvm=true loco.dev/gpu-dri=true
```

## WSL2/Docker Desktop Path

WSL2 supports a nested virtualization setting, but Docker Desktop/kind still
must expose `/dev/kvm` into the node container. Configure `%UserProfile%\.wslconfig`:

```ini
[wsl2]
nestedVirtualization=true
```

Then run:

```powershell
wsl --shutdown
```

Restart Docker Desktop and rerun the WSL/kind checks. If `/dev/kvm` is still
missing inside `loco-control-plane`, use Linux bare metal or another Kubernetes
node that exposes KVM.

## Cluster Proof

After rollout, verify:

```bash
kubectl exec -n loco loco-loco-emulator-0 -- test -e /dev/kvm
kubectl exec -n loco loco-loco-emulator-0 -- sh -lc "ping -c 2 192.168.10.11"
kubectl exec -n loco loco-loco-emulator-1 -- sh -lc "ping -c 2 192.168.10.10"
```
