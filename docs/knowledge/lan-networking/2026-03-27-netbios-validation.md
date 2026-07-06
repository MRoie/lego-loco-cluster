# NetBIOS/WINS Discovery Validation

**Date**: 2026-03-27  
**Author**: @lan-lead  
**Task**: L5  
**Status**: implemented  

## Summary

Created `k8s-tests/test-netbios.sh` to validate NetBIOS name resolution and subnet connectivity between all 9 LOCO emulator pods. The script follows the existing k8s-tests patterns (logging, graceful degradation in CI, kubectl-based execution) and tests the full chain from UDP/TCP port connectivity to workgroup browse list discovery.

## Test matrix

| # | Test | Protocol | What it validates |
|---|------|----------|-------------------|
| 1 | UDP 137 connectivity | UDP | NetBIOS Name Service port reachable between all pod pairs |
| 2 | UDP 138 connectivity | UDP | NetBIOS Datagram port reachable between all pod pairs |
| 3 | TCP 139 connectivity | TCP | NetBIOS Session Service port accepts connections |
| 4 | nmblookup per-name | UDP 137 | Each pod can resolve every other pod's hostname (LOCO-0N → 192.168.10.(10+N)) |
| 5 | Bridge traffic sniff | tcpdump | NetBIOS broadcast packets visible on loco-br |
| 6 | Workgroup browse | UDP 137 | LOCOLAND workgroup returns subnet members |
| 7 | Discovery matrix | UDP 137 | Full NxN table showing which names are visible from which pods |

## How it works

Tests run from the **host side** of each pod (the Linux container running QEMU), using `kubectl exec` to reach into pods. The script:

1. Discovers running `loco-emulator-*` pods in the namespace.
2. For each source-destination pod pair, tests port connectivity via `nc` / `nmap`.
3. Uses `nmblookup` (Samba client tool) to resolve NetBIOS names from the Linux side of the bridge.
4. Sniffs `loco-br` with `tcpdump` to verify Windows 98 guests are actually emitting NetBIOS broadcast traffic.
5. Queries the LOCOLAND workgroup for a browse list.
6. Prints a discovery matrix showing which pods can see which names.

## Dependencies

Tools expected inside the QEMU container image:

| Tool | Package | Purpose |
|------|---------|---------|
| `nc` (netcat) | netcat-openbsd | Port connectivity tests |
| `nmblookup` | samba-common-bin | NetBIOS name resolution |
| `tcpdump` | tcpdump | Bridge traffic capture |
| `nmap` (optional) | nmap | UDP port open detection |

If a tool is missing, the test degrades to WARN (not FAIL).

## Relationship to NetworkPolicy

The tests validate that `k8s/networkpolicy-game-ports.yaml` correctly allows ports 137-139 between emulator pods. If the policy is misconfigured, Tests 1-3 will report failures.

## Expected output (healthy cluster)

```
=== NetBIOS Test Summary ===
Total: 72+  Pass: 72+  Fail: 0  Warn: 0
✅ NetBIOS validation PASSED
```

With 9 pods and 7 test categories, the total check count scales as O(N²) for pair tests and O(N) for per-pod tests.

## Known limitations

- **Guest-side nbtstat**: Windows 98's `nbtstat -a` cannot be invoked programmatically from outside the VM without QEMU monitor integration (QMP). Test 5 uses bridge-level tcpdump as a proxy.
- **Timing**: Windows 98 NetBIOS name registration takes 30-60s after boot. Run this test after all instances have fully started.
- **CI environments**: Tests gracefully skip when fewer than 2 pods are running.
