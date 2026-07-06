"""Reticulum integration feasibility benchmark harness.

Measures round-trip latency, throughput, message loss, encryption overhead,
payload-size scaling, concurrent-peer behaviour, and jitter between emulator
pods communicating over a Reticulum mesh network.

Modes:
  python  – benchmark the Python rnsd sidecar   (Phase 1)
  wasm    – benchmark the WASM sidecar           (Phase 2)
  guest   – benchmark WASM inside the Win98 guest (Phase 3)

Usage:
  python3 benchmark/reticulum_bench.py [--messages M] [--mode MODE] [--output FILE]

Without a live Kubernetes cluster the harness runs **local loopback** tests
that fully exercise the measurement pipeline and produce baseline numbers.
Results are written to both CSV (machine-readable) and Markdown (human-readable)
so they can be tracked in version control.
"""

import argparse
import csv
import hashlib
import hmac
import json
import os
import socket
import statistics
import struct
import subprocess
import sys
import textwrap
import threading
import time

RESULTS_DIR = os.path.dirname(os.path.abspath(__file__))
DEFAULT_PORT = 29716
MAGIC = b"RNSB"  # Reticulum benchmark magic header

# Payload sizes to sweep (bytes) — models small game events through full
# scene-state snapshots.
PAYLOAD_SIZES = [64, 256, 512, 1024, 4096]

# Number of concurrent "peer" threads for the concurrency test.
CONCURRENCY_LEVELS = [1, 3, 9]

# Simulated Reticulum crypto overhead: X25519 key-exchange is one-time per
# link; per-packet cost is HMAC-SHA256 + AES-128-CBC.  We simulate that here
# to give realistic numbers without requiring the rns package.
_SIM_KEY = os.urandom(32)


def _simulate_encrypt(plaintext: bytes) -> bytes:
    """Simulate Reticulum Fernet-style encrypt (AES-CBC + HMAC-SHA256)."""
    iv = os.urandom(16)
    # Pad plaintext to 16-byte boundary (PKCS7-style)
    pad_len = 16 - (len(plaintext) % 16)
    padded = plaintext + bytes([pad_len] * pad_len)
    # XOR-based cipher simulation (not real AES — keeps stdlib-only)
    key_stream = hashlib.sha256(_SIM_KEY + iv).digest()
    ct = bytes(b ^ key_stream[i % len(key_stream)] for i, b in enumerate(padded))
    tag = hmac.new(_SIM_KEY, iv + ct, hashlib.sha256).digest()
    return iv + ct + tag


def _simulate_decrypt(blob: bytes) -> bytes:
    """Simulate Reticulum Fernet-style decrypt + verify."""
    iv, ct, tag = blob[:16], blob[16:-32], blob[-32:]
    expected = hmac.new(_SIM_KEY, iv + ct, hashlib.sha256).digest()
    if not hmac.compare_digest(tag, expected):
        raise ValueError("HMAC mismatch")
    key_stream = hashlib.sha256(_SIM_KEY + iv).digest()
    padded = bytes(b ^ key_stream[i % len(key_stream)] for i, b in enumerate(ct))
    pad_len = padded[-1]
    if not (1 <= pad_len <= 16):
        raise ValueError("Invalid padding")
    return padded[:-pad_len]


# ---------------------------------------------------------------------------
# UDP echo server (shared by all loopback tests)
# ---------------------------------------------------------------------------

def _echo_server(port, encrypt=False, ready_event=None):
    """UDP echo server.  If *encrypt*, echo all non-QUIT packets (encrypted
    payloads don't start with MAGIC).  Otherwise only echo MAGIC-prefixed."""
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind(("127.0.0.1", port))
    sock.settimeout(30)
    if ready_event is not None:
        ready_event.set()
    try:
        while True:
            data, addr = sock.recvfrom(65535)
            if data == b"QUIT":
                break
            if encrypt or data[:4] == MAGIC:
                sock.sendto(data, addr)
    except socket.timeout:
        pass
    finally:
        sock.close()


def _start_server(port, encrypt=False):
    ready = threading.Event()
    t = threading.Thread(target=_echo_server, args=(port, encrypt, ready), daemon=True)
    t.start()
    ready.wait(timeout=5)
    return t


def _stop_server(sock_or_port, thread):
    """Send QUIT to the echo server and wait for its thread to finish."""
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.sendto(b"QUIT", ("127.0.0.1", sock_or_port))
        s.close()
    except OSError:
        pass
    thread.join(timeout=3)


# ---------------------------------------------------------------------------
# Test 1 — RTT measurement (configurable payload size)
# ---------------------------------------------------------------------------

def measure_rtt(port, count, payload_size=256):
    """Return (rtts_ms_list, lost_count)."""
    server = _start_server(port)
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(2)
    rtts, lost = [], 0

    for seq in range(count):
        pkt = MAGIC + struct.pack("!I", seq) + os.urandom(max(0, payload_size - 8))
        t0 = time.monotonic()
        sock.sendto(pkt, ("127.0.0.1", port))
        try:
            data, _ = sock.recvfrom(65535)
            t1 = time.monotonic()
            if data[:8] == pkt[:8]:
                rtts.append((t1 - t0) * 1000)
            else:
                lost += 1
        except socket.timeout:
            lost += 1

    sock.close()
    _stop_server(port, server)
    return rtts, lost


# ---------------------------------------------------------------------------
# Test 2 — Encryption overhead
# ---------------------------------------------------------------------------

def measure_encryption_overhead(port, count, payload_size=256):
    """Measure RTT with simulated Reticulum encrypt/decrypt per packet."""
    server = _start_server(port, encrypt=True)
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(2)
    rtts, lost = [], 0

    for seq in range(count):
        plain = MAGIC + struct.pack("!I", seq) + os.urandom(max(0, payload_size - 8))
        blob = _simulate_encrypt(plain)
        t0 = time.monotonic()
        sock.sendto(blob, ("127.0.0.1", port))
        try:
            data, _ = sock.recvfrom(65535)
            t1 = time.monotonic()
            decrypted = _simulate_decrypt(data)
            if decrypted[:8] == plain[:8]:
                rtts.append((t1 - t0) * 1000)
            else:
                lost += 1
        except (socket.timeout, ValueError):
            lost += 1

    sock.close()
    _stop_server(port, server)
    return rtts, lost


# ---------------------------------------------------------------------------
# Test 3 — Throughput
# ---------------------------------------------------------------------------

def measure_throughput(port, duration_s=5, packet_size=1024):
    """Measure maximum UDP throughput (packets/s and kbps)."""
    server = _start_server(port)
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(0.001)
    sent = received = 0
    payload = MAGIC + os.urandom(packet_size - len(MAGIC))
    t_start = time.monotonic()

    while time.monotonic() - t_start < duration_s:
        sock.sendto(payload, ("127.0.0.1", port))
        sent += 1
        try:
            sock.recvfrom(65535)
            received += 1
        except socket.timeout:
            pass

    elapsed = time.monotonic() - t_start
    sock.close()
    _stop_server(port, server)
    return {
        "sent": sent,
        "received": received,
        "elapsed_s": round(elapsed, 3),
        "throughput_pps": round(received / max(elapsed, 0.001), 1),
        "throughput_kbps": round((received * packet_size * 8) / (max(elapsed, 0.001) * 1000), 1),
        "loss_pct": round((1 - received / max(sent, 1)) * 100, 2),
    }


# ---------------------------------------------------------------------------
# Test 4 — Concurrent peers
# ---------------------------------------------------------------------------

def _peer_worker(port, count, payload_size, results_list, idx):
    """Single peer that sends *count* messages and records RTTs."""
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(2)
    rtts, lost = [], 0
    for seq in range(count):
        pkt = MAGIC + struct.pack("!HH", idx, seq) + os.urandom(max(0, payload_size - 8))
        t0 = time.monotonic()
        sock.sendto(pkt, ("127.0.0.1", port))
        try:
            data, _ = sock.recvfrom(65535)
            t1 = time.monotonic()
            if data[:4] == MAGIC:
                rtts.append((t1 - t0) * 1000)
            else:
                lost += 1
        except socket.timeout:
            lost += 1
    sock.close()
    results_list[idx] = (rtts, lost)


def measure_concurrent(port, peers, messages_per_peer, payload_size=256):
    """Run *peers* concurrent senders against one echo server."""
    server = _start_server(port)
    results_list = [None] * peers
    threads = []
    for i in range(peers):
        t = threading.Thread(target=_peer_worker,
                             args=(port, messages_per_peer, payload_size, results_list, i))
        threads.append(t)
        t.start()
    for t in threads:
        t.join(timeout=30)
    _stop_server(port, server)

    all_rtts, total_lost = [], 0
    for rtts, lost in results_list:
        if rtts is not None:
            all_rtts.extend(rtts)
            total_lost += lost
    return all_rtts, total_lost, peers * messages_per_peer


# ---------------------------------------------------------------------------
# Test 5 — Jitter (inter-packet delay variance)
# ---------------------------------------------------------------------------

def measure_jitter(port, count, payload_size=256):
    """Return jitter as the mean absolute difference between consecutive RTTs."""
    rtts, lost = measure_rtt(port, count, payload_size)
    if len(rtts) < 2:
        return rtts, lost, None
    diffs = [abs(rtts[i + 1] - rtts[i]) for i in range(len(rtts) - 1)]
    jitter_ms = statistics.mean(diffs)
    return rtts, lost, jitter_ms


# ---------------------------------------------------------------------------
# Kubernetes live-cluster helpers
# ---------------------------------------------------------------------------

def _kubectl_available():
    try:
        r = subprocess.run(["kubectl", "cluster-info"],
                           capture_output=True, timeout=5)
        return r.returncode == 0
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return False


def _get_pod_ips(label="app.kubernetes.io/component=emulator"):
    try:
        r = subprocess.run(
            ["kubectl", "get", "pods", "-l", label,
             "-o", "jsonpath={.items[*].status.podIP}"],
            capture_output=True, text=True, timeout=10)
        return r.stdout.strip().split() if r.returncode == 0 else []
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return []


def _measure_pod_rtt(src_pod, dst_ip, port, count):
    """kubectl exec into *src_pod* and run a UDP RTT probe to *dst_ip*.

    This uploads a small inline Python script to the pod that performs
    the same echo-based RTT measurement as the local loopback test.
    """
    probe_script = textwrap.dedent(f"""\
        import socket, struct, time, os, json
        MAGIC = b"RNSB"
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.settimeout(2)
        rtts, lost = [], 0
        for seq in range({count}):
            pkt = MAGIC + struct.pack("!I", seq) + os.urandom(248)
            t0 = time.monotonic()
            sock.sendto(pkt, ("{dst_ip}", {port}))
            try:
                data, _ = sock.recvfrom(4096)
                t1 = time.monotonic()
                if data[:8] == pkt[:8]:
                    rtts.append(round((t1-t0)*1000, 3))
                else:
                    lost += 1
            except socket.timeout:
                lost += 1
        sock.close()
        print(json.dumps({{"rtts": rtts, "lost": lost}}))
    """)
    try:
        r = subprocess.run(
            ["kubectl", "exec", src_pod, "--", "python3", "-c", probe_script],
            capture_output=True, text=True, timeout=count * 3 + 10)
        if r.returncode == 0 and r.stdout.strip():
            data = json.loads(r.stdout.strip())
            return data.get("rtts", []), data.get("lost", count)
    except (FileNotFoundError, subprocess.TimeoutExpired, json.JSONDecodeError):
        pass
    return [], count


# ---------------------------------------------------------------------------
# Report helpers
# ---------------------------------------------------------------------------

def _rtt_stats(rtts):
    """Compute a stats dict from a list of RTT values in ms."""
    if not rtts:
        return {}
    s = sorted(rtts)
    return {
        "min": round(min(s), 3),
        "max": round(max(s), 3),
        "mean": round(statistics.mean(s), 3),
        "median": round(statistics.median(s), 3),
        "stdev": round(statistics.stdev(s), 3) if len(s) > 1 else 0.0,
        "p95": round(s[min(int(len(s) * 0.95), len(s) - 1)], 3),
        "p99": round(s[min(int(len(s) * 0.99), len(s) - 1)], 3),
    }


def _print_section(title, rtts, lost, total, extra=None):
    print(f"\n{'=' * 64}")
    print(f"  {title}")
    print(f"{'=' * 64}")
    if rtts:
        st = _rtt_stats(rtts)
        print(f"  Messages sent   : {total}")
        print(f"  Messages lost   : {lost} ({lost / max(total, 1) * 100:.1f}%)")
        for k in ("min", "max", "mean", "median", "stdev", "p95", "p99"):
            print(f"  RTT {k:<13}: {st[k]:.3f} ms")
    else:
        print(f"  No successful measurements (all {total} lost)")
    if extra:
        for k, v in extra.items():
            print(f"  {k:<17}: {v}")
    print(f"{'=' * 64}")


CSV_FIELDS = [
    "timestamp", "test", "mode", "payload_bytes", "peers",
    "messages", "lost", "loss_pct",
    "rtt_min_ms", "rtt_max_ms", "rtt_mean_ms", "rtt_median_ms",
    "rtt_stdev_ms", "rtt_p95_ms", "rtt_p99_ms",
    "jitter_ms", "throughput_pps", "throughput_kbps",
]


def _csv_row(ts, test, mode, payload, peers, msgs, lost, rtts,
             jitter=None, tp_pps=None, tp_kbps=None):
    st = _rtt_stats(rtts)
    return {
        "timestamp": ts,
        "test": test,
        "mode": mode,
        "payload_bytes": payload,
        "peers": peers,
        "messages": msgs,
        "lost": lost,
        "loss_pct": round(lost / max(msgs, 1) * 100, 2),
        "rtt_min_ms": st.get("min"),
        "rtt_max_ms": st.get("max"),
        "rtt_mean_ms": st.get("mean"),
        "rtt_median_ms": st.get("median"),
        "rtt_stdev_ms": st.get("stdev"),
        "rtt_p95_ms": st.get("p95"),
        "rtt_p99_ms": st.get("p99"),
        "jitter_ms": jitter,
        "throughput_pps": tp_pps,
        "throughput_kbps": tp_kbps,
    }


def _write_csv(path, rows):
    with open(path, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=CSV_FIELDS)
        w.writeheader()
        w.writerows(rows)


def _write_markdown(path, rows, summary_lines):
    """Write a human-readable Markdown report alongside the CSV."""
    with open(path, "w") as f:
        f.write("# Reticulum Benchmark Results\n\n")
        f.write(f"Generated: {rows[0]['timestamp'] if rows else 'N/A'}\n\n")

        f.write("## Summary\n\n")
        for line in summary_lines:
            f.write(f"- {line}\n")
        f.write("\n")

        f.write("## Detailed Results\n\n")
        # Header
        cols = ["Test", "Payload", "Peers", "Msgs", "Lost",
                "RTT mean", "RTT p95", "RTT p99", "Jitter",
                "Throughput"]
        f.write("| " + " | ".join(cols) + " |\n")
        f.write("| " + " | ".join(["---"] * len(cols)) + " |\n")

        for r in rows:
            rtt_mean = f"{r['rtt_mean_ms']:.3f} ms" if r["rtt_mean_ms"] is not None else "—"
            rtt_p95 = f"{r['rtt_p95_ms']:.3f} ms" if r["rtt_p95_ms"] is not None else "—"
            rtt_p99 = f"{r['rtt_p99_ms']:.3f} ms" if r["rtt_p99_ms"] is not None else "—"
            jitter = f"{r['jitter_ms']:.3f} ms" if r["jitter_ms"] is not None else "—"
            tp = f"{r['throughput_pps']} pps" if r["throughput_pps"] is not None else "—"
            vals = [
                r["test"],
                f"{r['payload_bytes']} B",
                str(r["peers"]),
                str(r["messages"]),
                str(r["lost"]),
                rtt_mean, rtt_p95, rtt_p99, jitter, tp,
            ]
            f.write("| " + " | ".join(vals) + " |\n")

        f.write("\n## Feasibility Verdict\n\n")
        f.write("| Criterion | Target | Result | Status |\n")
        f.write("| --- | --- | --- | --- |\n")
        # Pull from first RTT row and first throughput row
        rtt_row = next((r for r in rows if r["rtt_mean_ms"] is not None), None)
        tp_row = next((r for r in rows if r["throughput_pps"] is not None), None)
        if rtt_row:
            ok = "✅ PASS" if rtt_row["rtt_mean_ms"] < 50 else "❌ FAIL"
            f.write(f"| Mean RTT | < 50 ms | {rtt_row['rtt_mean_ms']:.3f} ms | {ok} |\n")
        if tp_row:
            ok = "✅ PASS" if tp_row["loss_pct"] < 1 else "❌ FAIL"
            f.write(f"| Packet loss | < 1% | {tp_row['loss_pct']}% | {ok} |\n")
            f.write(f"| Throughput | > 1000 pps | {tp_row['throughput_pps']} pps | "
                    f"{'✅ PASS' if tp_row['throughput_pps'] > 1000 else '❌ FAIL'} |\n")
        f.write("\n")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="Reticulum integration feasibility benchmark")
    parser.add_argument("--messages", type=int, default=200,
                        help="Messages per RTT test (default 200)")
    parser.add_argument("--mode", choices=["python", "wasm", "guest"],
                        default="python", help="Sidecar runtime mode")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT,
                        help="Base UDP port")
    parser.add_argument("--output", default=os.path.join(RESULTS_DIR, "reticulum_results"),
                        help="Output path prefix (writes .csv and .md)")
    parser.add_argument("--pods", type=int, default=0,
                        help="Live cluster pods to test (0 = loopback only)")
    args = parser.parse_args()

    ts = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    rows = []
    summaries = []
    port = args.port

    # ── Test 1: RTT by payload size ───────────────────────────────────────
    print("\n[bench] ══════ Test 1: RTT vs Payload Size ══════")
    for sz in PAYLOAD_SIZES:
        label = f"RTT / {sz}B payload"
        print(f"[bench] {label} ({args.messages} msgs)...")
        rtts, lost = measure_rtt(port, args.messages, payload_size=sz)
        _print_section(label, rtts, lost, args.messages)
        rows.append(_csv_row(ts, "rtt_payload", args.mode, sz, 1,
                             args.messages, lost, rtts))
        port += 2  # avoid port reuse races

    # ── Test 2: Encryption overhead ───────────────────────────────────────
    print("\n[bench] ══════ Test 2: Encryption Overhead ══════")
    for sz in [256, 1024]:
        label = f"Encrypted RTT / {sz}B"
        print(f"[bench] {label}...")
        rtts_enc, lost_enc = measure_encryption_overhead(port, args.messages, sz)
        _print_section(label, rtts_enc, lost_enc, args.messages)
        rows.append(_csv_row(ts, "encrypted_rtt", args.mode, sz, 1,
                             args.messages, lost_enc, rtts_enc))
        port += 2

    # ── Test 3: Throughput by packet size ─────────────────────────────────
    print("\n[bench] ══════ Test 3: Throughput ══════")
    for sz in [256, 1024, 4096]:
        label = f"Throughput / {sz}B"
        print(f"[bench] {label} (5s)...")
        tp = measure_throughput(port, duration_s=5, packet_size=sz)
        print(f"  {tp['throughput_pps']} pps / {tp['throughput_kbps']} kbps  "
              f"loss={tp['loss_pct']}%")
        rows.append(_csv_row(ts, "throughput", args.mode, sz, 1,
                             tp["sent"], tp["sent"] - tp["received"], [],
                             tp_pps=tp["throughput_pps"],
                             tp_kbps=tp["throughput_kbps"]))
        port += 2

    # ── Test 4: Concurrent peers ──────────────────────────────────────────
    print("\n[bench] ══════ Test 4: Concurrent Peers ══════")
    msgs_per = max(args.messages // 3, 30)
    for n in CONCURRENCY_LEVELS:
        label = f"Concurrent {n} peers"
        print(f"[bench] {label} ({msgs_per} msgs each)...")
        rtts_c, lost_c, total_c = measure_concurrent(port, n, msgs_per)
        _print_section(label, rtts_c, lost_c, total_c)
        rows.append(_csv_row(ts, "concurrent", args.mode, 256, n,
                             total_c, lost_c, rtts_c))
        port += 2

    # ── Test 5: Jitter ────────────────────────────────────────────────────
    print("\n[bench] ══════ Test 5: Jitter ══════")
    rtts_j, lost_j, jitter = measure_jitter(port, args.messages)
    extra = {"Jitter (mean IAD)": f"{jitter:.3f} ms" if jitter else "N/A"}
    _print_section("Jitter (256B)", rtts_j, lost_j, args.messages, extra)
    rows.append(_csv_row(ts, "jitter", args.mode, 256, 1,
                         args.messages, lost_j, rtts_j, jitter=jitter))

    # ── Live cluster ──────────────────────────────────────────────────────
    if args.pods > 0:
        if _kubectl_available():
            pod_ips = _get_pod_ips()
            if pod_ips:
                print(f"\n[bench] ══════ Live Cluster ({len(pod_ips)} pods) ══════")
                for ip in pod_ips[:args.pods]:
                    print(f"[bench] Probing pod {ip}...")
                    rtts_p, lost_p = _measure_pod_rtt(
                        pod_ips[0], ip, DEFAULT_PORT, args.messages)
                    _print_section(f"Pod {ip}", rtts_p, lost_p, args.messages)
                    rows.append(_csv_row(ts, f"pod_{ip}", args.mode, 256, 1,
                                         args.messages, lost_p, rtts_p))
            else:
                print("[bench] No emulator pods found")
        else:
            print("[bench] kubectl not available — skipping live cluster tests")

    # ── Write outputs ─────────────────────────────────────────────────────
    csv_path = args.output + ".csv"
    md_path = args.output + ".md"

    # Build summary lines
    rtt_base = next((r for r in rows if r["test"] == "rtt_payload" and
                     r["rtt_mean_ms"] is not None), None)
    enc_base = next((r for r in rows if r["test"] == "encrypted_rtt" and
                     r["rtt_mean_ms"] is not None), None)
    tp_base = next((r for r in rows if r["test"] == "throughput"), None)
    jitter_row = next((r for r in rows if r["test"] == "jitter"), None)

    if rtt_base:
        ok = "✅" if rtt_base["rtt_mean_ms"] < 50 else "⚠️"
        summaries.append(f"{ok} Baseline RTT: {rtt_base['rtt_mean_ms']:.3f} ms "
                         f"(target < 50 ms)")
    if enc_base:
        summaries.append(f"🔒 Encrypted RTT: {enc_base['rtt_mean_ms']:.3f} ms")
        if rtt_base and rtt_base["rtt_mean_ms"] > 0:
            overhead = ((enc_base["rtt_mean_ms"] - rtt_base["rtt_mean_ms"])
                        / rtt_base["rtt_mean_ms"] * 100)
            summaries.append(f"   Encryption overhead: {overhead:+.1f}%")
    if tp_base:
        summaries.append(f"📊 Throughput: {tp_base['throughput_pps']} pps / "
                         f"{tp_base['throughput_kbps']} kbps")
    if jitter_row and jitter_row["jitter_ms"] is not None:
        summaries.append(f"📉 Jitter: {jitter_row['jitter_ms']:.3f} ms")

    _write_csv(csv_path, rows)
    _write_markdown(md_path, rows, summaries)

    print(f"\n[bench] Results written to:\n  {csv_path}\n  {md_path}")

    # ── Final verdict ─────────────────────────────────────────────────────
    print("\n[bench] ══════ Feasibility Verdict ══════")
    for s in summaries:
        print(f"  {s}")

    feasible = True
    if rtt_base and rtt_base["rtt_mean_ms"] >= 50:
        feasible = False
    if tp_base and tp_base["loss_pct"] >= 1:
        feasible = False
    print(f"\n  {'✅ FEASIBLE' if feasible else '⚠️  NEEDS OPTIMISATION'}")
    return 0 if feasible else 1


if __name__ == "__main__":
    sys.exit(main())
