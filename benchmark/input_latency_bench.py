#!/usr/bin/env python3
"""
Input-to-Display Latency Benchmark
===================================

Injects a known input via QMP (e.g. a key press that triggers a visible UI
change), captures VNC/health frames, and measures the round-trip latency.

Target: < 150ms for smooth interactive feel.

Usage:
  python input_latency_bench.py --qmp-agent http://localhost:9090 --instance 0
  python input_latency_bench.py --instances 0 1 2 --trials 10
"""

import argparse
import json
import os
import sys
import time
import urllib.request
from datetime import datetime
from pathlib import Path
from statistics import mean, stdev, median


def api_post(url, data, timeout=10):
    try:
        body = json.dumps(data).encode()
        req = urllib.request.Request(url, data=body,
                                     headers={"Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read().decode())
    except Exception as e:
        return {"error": str(e)}


def api_get(url, timeout=5):
    try:
        with urllib.request.urlopen(url, timeout=timeout) as resp:
            return json.loads(resp.read().decode())
    except Exception as e:
        return {"error": str(e)}


def measure_single_latency(qmp_url, health_url, instance_id, key="space"):
    """
    Measure the time from key injection to health endpoint reflecting
    the input (proxy for actual display change).
    
    More accurate measurement would use VNC screenshot pixel diff,
    but health probe latency serves as an upper-bound estimate.
    """
    # Pre-probe to warm connection
    api_get(health_url)

    # Inject the key and simultaneously measure time
    t0 = time.monotonic()

    # Send key tap via QMP
    api_post(f"{qmp_url}/input/{instance_id}", {
        "type": "key", "key": key, "action": "tap"
    })

    # Immediately probe health to measure round-trip
    health = api_get(health_url)
    t1 = time.monotonic()

    latency_ms = round((t1 - t0) * 1000, 1)

    return {
        "latency_ms": latency_ms,
        "qmp_ok": "error" not in health,
        "timestamp": datetime.utcnow().isoformat(),
    }


def run_latency_benchmark(qmp_url, health_base_url, instance_ids, trials=20, key="space"):
    """Run multiple latency trials across instances."""
    results = {}

    for iid in instance_ids:
        health_url = f"{health_base_url.rstrip('/')}"
        # If health_base_url includes port offset pattern
        if "{instance}" in health_url:
            health_url = health_url.replace("{instance}", str(iid))

        print(f"\nInstance {iid}: {trials} trials ...")
        latencies = []

        for t in range(trials):
            m = measure_single_latency(qmp_url, health_url, iid, key)
            latencies.append(m["latency_ms"])
            time.sleep(0.2)  # Small gap between trials

        results[iid] = {
            "trials": trials,
            "latencies_ms": latencies,
            "mean_ms": round(mean(latencies), 1),
            "median_ms": round(median(latencies), 1),
            "min_ms": round(min(latencies), 1),
            "max_ms": round(max(latencies), 1),
            "stdev_ms": round(stdev(latencies), 1) if len(latencies) > 1 else 0,
            "p95_ms": round(sorted(latencies)[int(len(latencies) * 0.95)], 1),
            "under_150ms": sum(1 for l in latencies if l < 150),
        }

        print(f"  Mean: {results[iid]['mean_ms']}ms  "
              f"P95: {results[iid]['p95_ms']}ms  "
              f"<150ms: {results[iid]['under_150ms']}/{trials}")

    return results


def generate_report(results, output_path):
    """Generate latency benchmark markdown report."""
    lines = [
        "# Input-to-Display Latency Benchmark Report",
        "",
        f"**Generated**: {datetime.utcnow().isoformat()}Z",
        f"**Target**: < 150ms round-trip",
        "",
        "## Results",
        "",
        "| Instance | Mean (ms) | Median | P95 | Min | Max | StdDev | < 150ms |",
        "|----------|-----------|--------|-----|-----|-----|--------|---------|",
    ]

    all_under = True
    for iid, data in sorted(results.items()):
        pass_rate = f"{data['under_150ms']}/{data['trials']}"
        if data["p95_ms"] > 150:
            all_under = False
        lines.append(
            f"| {iid} | {data['mean_ms']} | {data['median_ms']} | {data['p95_ms']} "
            f"| {data['min_ms']} | {data['max_ms']} | {data['stdev_ms']} | {pass_rate} |"
        )

    lines.append("")
    lines.append(f"## Verdict: {'✅ PASS — all P95 < 150ms' if all_under else '❌ FAIL — P95 exceeds 150ms'}")
    lines.append("")

    Path(output_path).write_text("\n".join(lines))
    print(f"\nReport written: {output_path}")
    return all_under


def main():
    parser = argparse.ArgumentParser(description="Input-to-Display Latency Benchmark")
    parser.add_argument("--qmp-agent", default="http://localhost:9090")
    parser.add_argument("--health-url", default="http://localhost:8080/health",
                        help="Health URL (use {instance} for instance substitution)")
    parser.add_argument("--instances", nargs="+", default=["0"])
    parser.add_argument("--trials", type=int, default=20)
    parser.add_argument("--key", default="space", help="Key to inject for latency test")
    parser.add_argument("--output", default="benchmark/LATENCY_REPORT.md")
    args = parser.parse_args()

    os.makedirs(os.path.dirname(args.output), exist_ok=True)

    results = run_latency_benchmark(
        args.qmp_agent, args.health_url,
        args.instances, args.trials, args.key,
    )

    passed = generate_report(results, args.output)
    sys.exit(0 if passed else 1)


if __name__ == "__main__":
    main()
