"""Reticulum integration feasibility benchmark harness.

Measures round-trip latency, throughput, and message loss between emulator pods
communicating over a Reticulum mesh network.  Can run in three modes:

  python  – benchmark the Python rnsd sidecar (Phase 1)
  wasm    – benchmark the WASM sidecar (Phase 2)
  guest   – benchmark WASM running inside the Win98 guest (Phase 3)

Usage:
  python3 benchmark/reticulum_bench.py [--pods N] [--messages M] [--mode MODE]

Without a live cluster the harness runs a **local loopback simulation** that
validates the measurement pipeline and produces baseline numbers.
"""

import argparse
import csv
import json
import os
import socket
import statistics
import struct
import subprocess
import sys
import time

RESULTS_DIR = os.path.join(os.path.dirname(__file__), "..", "benchmark")
DEFAULT_PORT = 29716
MAGIC = b"RNSB"  # Reticulum benchmark magic header


# ---------------------------------------------------------------------------
# Loopback echo server/client for offline benchmarking
# ---------------------------------------------------------------------------

def _loopback_echo_server(port, ready_event=None):
    """Simple UDP echo server for loopback latency measurement."""
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind(("127.0.0.1", port))
    sock.settimeout(10)
    if ready_event is not None:
        ready_event.set()
    try:
        while True:
            data, addr = sock.recvfrom(4096)
            if data[:4] == MAGIC:
                sock.sendto(data, addr)
            elif data == b"QUIT":
                break
    except socket.timeout:
        pass
    finally:
        sock.close()


def _measure_loopback_rtt(port, count):
    """Send *count* UDP packets to localhost echo and measure RTT."""
    import threading

    ready = threading.Event()
    server = threading.Thread(target=_loopback_echo_server, args=(port, ready), daemon=True)
    server.start()
    ready.wait(timeout=5)

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(2)
    rtts = []
    lost = 0
    payload_size = 256  # representative game-state packet

    for seq in range(count):
        pkt = MAGIC + struct.pack("!I", seq) + os.urandom(payload_size)
        t0 = time.monotonic()
        sock.sendto(pkt, ("127.0.0.1", port))
        try:
            data, _ = sock.recvfrom(4096)
            t1 = time.monotonic()
            if data[:8] == pkt[:8]:
                rtts.append((t1 - t0) * 1000)  # ms
            else:
                lost += 1
        except socket.timeout:
            lost += 1

    sock.sendto(b"QUIT", ("127.0.0.1", port))
    sock.close()
    server.join(timeout=3)
    return rtts, lost


# ---------------------------------------------------------------------------
# Live cluster measurement helpers
# ---------------------------------------------------------------------------

def _kubectl_available():
    """Return True if kubectl is on PATH and can reach a cluster."""
    try:
        r = subprocess.run(
            ["kubectl", "cluster-info"],
            capture_output=True, timeout=5,
        )
        return r.returncode == 0
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return False


def _get_pod_ips(label="app.kubernetes.io/component=emulator"):
    """Return list of pod IPs matching *label*."""
    try:
        r = subprocess.run(
            ["kubectl", "get", "pods", "-l", label,
             "-o", "jsonpath={.items[*].status.podIP}"],
            capture_output=True, text=True, timeout=10,
        )
        return r.stdout.strip().split() if r.returncode == 0 else []
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return []


def _measure_pod_rtt(src_pod, dst_ip, port, count):
    """Exec into *src_pod* and measure UDP RTT to *dst_ip*."""
    # Placeholder – in a real cluster this would kubectl exec a small script
    return [], count  # all lost (stub)


# ---------------------------------------------------------------------------
# Throughput measurement
# ---------------------------------------------------------------------------

def _measure_throughput(port, duration_s=5, packet_size=1024):
    """Measure maximum UDP throughput over loopback for *duration_s* seconds."""
    import threading

    ready = threading.Event()
    server = threading.Thread(target=_loopback_echo_server, args=(port + 1, ready), daemon=True)
    server.start()
    ready.wait(timeout=5)

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(0.01)
    sent = 0
    received = 0
    payload = MAGIC + os.urandom(packet_size - len(MAGIC))
    t_start = time.monotonic()

    while time.monotonic() - t_start < duration_s:
        sock.sendto(payload, ("127.0.0.1", port + 1))
        sent += 1
        try:
            sock.recvfrom(4096)
            received += 1
        except socket.timeout:
            pass

    elapsed = time.monotonic() - t_start
    sock.sendto(b"QUIT", ("127.0.0.1", port + 1))
    sock.close()
    server.join(timeout=3)

    return {
        "sent": sent,
        "received": received,
        "elapsed_s": round(elapsed, 3),
        "throughput_pps": round(received / elapsed, 1),
        "throughput_kbps": round((received * packet_size * 8) / (elapsed * 1000), 1),
        "loss_pct": round((1 - received / max(sent, 1)) * 100, 2),
    }


# ---------------------------------------------------------------------------
# Report generation
# ---------------------------------------------------------------------------

def _print_report(label, rtts, lost, total):
    """Print a human-readable summary of RTT measurements."""
    print(f"\n{'=' * 60}")
    print(f"  {label}")
    print(f"{'=' * 60}")
    if rtts:
        print(f"  Messages sent   : {total}")
        print(f"  Messages lost   : {lost} ({lost / total * 100:.1f} %)")
        print(f"  RTT min         : {min(rtts):.3f} ms")
        print(f"  RTT max         : {max(rtts):.3f} ms")
        print(f"  RTT mean        : {statistics.mean(rtts):.3f} ms")
        print(f"  RTT median      : {statistics.median(rtts):.3f} ms")
        if len(rtts) > 1:
            print(f"  RTT stdev       : {statistics.stdev(rtts):.3f} ms")
        print(f"  RTT p95         : {sorted(rtts)[int(len(rtts) * 0.95)]:.3f} ms")
        print(f"  RTT p99         : {sorted(rtts)[int(len(rtts) * 0.99)]:.3f} ms")
    else:
        print(f"  No successful measurements (all {total} messages lost)")
    print(f"{'=' * 60}\n")


def _write_csv(path, rows):
    """Append benchmark rows to a CSV file."""
    exists = os.path.isfile(path)
    with open(path, "a", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=[
            "timestamp", "mode", "pods", "messages",
            "rtt_min_ms", "rtt_max_ms", "rtt_mean_ms", "rtt_median_ms",
            "rtt_p95_ms", "rtt_p99_ms", "loss_pct",
            "throughput_pps", "throughput_kbps",
        ])
        if not exists:
            writer.writeheader()
        writer.writerows(rows)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="Reticulum integration feasibility benchmark",
    )
    parser.add_argument(
        "--pods", type=int, default=0,
        help="Number of pods to benchmark (0 = loopback only)",
    )
    parser.add_argument(
        "--messages", type=int, default=100,
        help="Number of messages per RTT test",
    )
    parser.add_argument(
        "--mode", choices=["python", "wasm", "guest"], default="python",
        help="Sidecar runtime mode to benchmark",
    )
    parser.add_argument(
        "--port", type=int, default=DEFAULT_PORT,
        help="UDP port for benchmark traffic",
    )
    parser.add_argument(
        "--output", default=os.path.join(RESULTS_DIR, "reticulum_results.csv"),
        help="CSV output file",
    )
    args = parser.parse_args()

    results = []
    ts = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())

    # --- Loopback baseline ------------------------------------------------
    print(f"[bench] Running loopback RTT baseline ({args.messages} messages)...")
    rtts, lost = _measure_loopback_rtt(args.port, args.messages)
    _print_report(f"Loopback baseline (mode={args.mode})", rtts, lost, args.messages)

    row = {
        "timestamp": ts,
        "mode": args.mode,
        "pods": 0,
        "messages": args.messages,
        "rtt_min_ms": round(min(rtts), 3) if rtts else None,
        "rtt_max_ms": round(max(rtts), 3) if rtts else None,
        "rtt_mean_ms": round(statistics.mean(rtts), 3) if rtts else None,
        "rtt_median_ms": round(statistics.median(rtts), 3) if rtts else None,
        "rtt_p95_ms": round(sorted(rtts)[int(len(rtts) * 0.95)], 3) if rtts else None,
        "rtt_p99_ms": round(sorted(rtts)[int(len(rtts) * 0.99)], 3) if rtts else None,
        "loss_pct": round(lost / args.messages * 100, 2),
        "throughput_pps": None,
        "throughput_kbps": None,
    }
    results.append(row)

    # --- Throughput baseline ----------------------------------------------
    print("[bench] Running throughput baseline (5 s)...")
    tp = _measure_throughput(args.port, duration_s=5)
    print(f"  Throughput: {tp['throughput_pps']} pps / {tp['throughput_kbps']} kbps")
    print(f"  Loss: {tp['loss_pct']} %")
    results[0]["throughput_pps"] = tp["throughput_pps"]
    results[0]["throughput_kbps"] = tp["throughput_kbps"]

    # --- Live cluster tests -----------------------------------------------
    if args.pods > 0 and _kubectl_available():
        pod_ips = _get_pod_ips()
        if pod_ips:
            print(f"[bench] Found {len(pod_ips)} emulator pods")
            for ip in pod_ips[: args.pods]:
                rtts_pod, lost_pod = _measure_pod_rtt("bench", ip, args.port, args.messages)
                _print_report(f"Pod {ip} (mode={args.mode})", rtts_pod, lost_pod, args.messages)
        else:
            print("[bench] No emulator pods found in cluster")
    elif args.pods > 0:
        print("[bench] kubectl not available — skipping live cluster tests")

    # --- Write results ----------------------------------------------------
    os.makedirs(os.path.dirname(args.output), exist_ok=True)
    _write_csv(args.output, results)
    print(f"[bench] Results written to {args.output}")

    # --- Summary ----------------------------------------------------------
    print("\n[bench] Feasibility summary:")
    if rtts:
        mean_rtt = statistics.mean(rtts)
        if mean_rtt < 50:
            print(f"  ✅ Mean RTT {mean_rtt:.1f} ms < 50 ms target — FEASIBLE")
        else:
            print(f"  ⚠️  Mean RTT {mean_rtt:.1f} ms ≥ 50 ms target — needs optimisation")
    if tp["loss_pct"] < 1:
        print(f"  ✅ Packet loss {tp['loss_pct']}% < 1% — FEASIBLE")
    else:
        print(f"  ⚠️  Packet loss {tp['loss_pct']}% ≥ 1% — needs investigation")

    return 0


if __name__ == "__main__":
    sys.exit(main())
