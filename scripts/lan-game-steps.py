#!/usr/bin/env python3
"""Drive Win98 guests into a Lego Loco LAN game via QMP, with proof capture.

Executes step files against emulator pods using `kubectl exec` and the
qmp-control.py helper baked into the emulator image. Step files are plain
text, one command per line (`#` comments allowed):

    <instance> hmp <monitor command...>   raw HMP (mouse_move, sendkey, ...)
    <instance> loadvm <tag>               restore a savevm snapshot
    <instance> sleep <seconds>            wait
    <instance> dump <label>               screendump -> proof dir (ppm + png)

The shipped host-create/guest-join step files encode the choreography from
docs/LAN_MULTIPLAYER_AND_GHCR_RUNBOOK.md §2.4 at 1024x768. Coordinates are
resolution-dependent — recapture with `dump` steps if the layout changes.
"""

import argparse
import subprocess
import sys
import time
from pathlib import Path

QMP_HELPER = "/usr/local/bin/qmp-control.py"


def kubectl_exec(namespace, pod, *cmd, check=True):
    full = ["kubectl", "exec", "-n", namespace, pod, "--", *cmd]
    result = subprocess.run(full, capture_output=True, text=True, timeout=120)
    if check and result.returncode != 0:
        raise RuntimeError(f"{' '.join(full)} failed: {result.stderr.strip()}")
    return result.stdout


def pod_name(namespace, index):
    return f"loco-loco-emulator-{index}"


def screendump(namespace, pod, label, proof_dir):
    remote = f"/tmp/proof-{label}.ppm"
    kubectl_exec(namespace, pod, "python3", QMP_HELPER, "hmp", f"screendump {remote}")
    time.sleep(1)
    local_ppm = proof_dir / f"{pod}-{label}.ppm"
    subprocess.run(
        ["kubectl", "cp", "-n", namespace, f"{pod}:{remote.lstrip('/')}", str(local_ppm)],
        capture_output=True, text=True, timeout=120,
    )
    if not local_ppm.exists():
        print(f"  WARNING: could not copy {remote} from {pod}")
        return
    try:
        from PIL import Image
        png = local_ppm.with_suffix(".png")
        Image.open(local_ppm).save(png)
        local_ppm.unlink()
        print(f"  proof: {png}")
    except ImportError:
        print(f"  proof: {local_ppm} (install pillow for png conversion)")


def run_steps(namespace, steps_file, proof_dir, label):
    print(f"--- running {steps_file} ({label})")
    for raw in Path(steps_file).read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split(None, 2)
        idx, cmd = parts[0], parts[1]
        arg = parts[2] if len(parts) > 2 else ""
        pod = pod_name(namespace, idx)

        if cmd == "sleep":
            time.sleep(float(arg))
        elif cmd == "hmp":
            out = kubectl_exec(namespace, pod, "python3", QMP_HELPER, "hmp", arg)
            if '"error"' in out:
                print(f"  WARNING [{pod}] hmp {arg}: {out.strip()[:120]}")
        elif cmd == "loadvm":
            print(f"  [{pod}] loadvm {arg}")
            out = kubectl_exec(namespace, pod, "python3", QMP_HELPER, "loadvm", arg, check=False)
            if '"error"' in out:
                print(f"  WARNING [{pod}] loadvm {arg} failed — continuing from live state")
        elif cmd == "dump":
            screendump(namespace, pod, arg, proof_dir)
        else:
            print(f"  WARNING: unknown step command: {line}")


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--namespace", default="loco")
    ap.add_argument("--proof-dir", default="proof")
    ap.add_argument("--host-steps", required=True)
    ap.add_argument("--guest-steps", required=True)
    ap.add_argument("--settle", type=float, default=8.0,
                    help="seconds to wait between host-create and guest-join")
    args = ap.parse_args()

    proof_dir = Path(args.proof_dir)
    proof_dir.mkdir(parents=True, exist_ok=True)

    run_steps(args.namespace, args.host_steps, proof_dir, "host creates LAN game")
    print(f"--- waiting {args.settle}s for the session to open")
    time.sleep(args.settle)
    run_steps(args.namespace, args.guest_steps, proof_dir, "guest joins LAN game")

    # Final proof: both screens after the join settles
    time.sleep(10)
    for idx in (0, 1):
        screendump(args.namespace, pod_name(args.namespace, idx), "final", proof_dir)

    print("--- LAN game choreography complete")


if __name__ == "__main__":
    sys.exit(main())
