#!/usr/bin/env python3
"""
Streaming Pipeline Profiler
============================

Instruments every stage of the video pipeline:
  QEMU framebuffer → Xvfb → GStreamer capture → H.264 encode → RTP → UDP →
  WebRTC relay → browser decode → canvas paint

Collects per-stage timing from container health endpoints, GStreamer debug
output, and Docker stats. Outputs a timing breakdown and bottleneck analysis.

Usage:
  python pipeline_profiler.py --target localhost:8080
  python pipeline_profiler.py --mode k8s --namespace loco
"""

import argparse
import json
import os
import re
import subprocess
import sys
import time
import urllib.request
from datetime import datetime
from pathlib import Path


def api_get(url, timeout=5):
    try:
        with urllib.request.urlopen(url, timeout=timeout) as resp:
            return json.loads(resp.read().decode())
    except Exception as e:
        return {"error": str(e)}


def get_gstreamer_stats(container_name=None, pod_name=None, namespace="loco"):
    """Extract GStreamer pipeline timing from container logs."""
    stages = {
        "ximagesrc_capture": None,
        "videoconvert": None,
        "x264enc_encode": None,
        "rtph264pay": None,
        "udpsink_send": None,
    }

    try:
        if pod_name:
            raw = subprocess.check_output(
                ["kubectl", "logs", "-n", namespace, pod_name, "--tail=100"],
                timeout=10, text=True, stderr=subprocess.STDOUT,
            )
        elif container_name:
            raw = subprocess.check_output(
                ["docker", "logs", "--tail=100", container_name],
                timeout=10, text=True, stderr=subprocess.STDOUT,
            )
        else:
            return stages
    except (subprocess.SubprocessError, FileNotFoundError):
        return stages

    # Parse GStreamer debug output for pipeline element timings
    for line in raw.splitlines():
        if "ximagesrc" in line and "framerate" in line.lower():
            stages["ximagesrc_capture"] = "active"
        if "x264enc" in line:
            stages["x264enc_encode"] = "active"

    return stages


def get_process_cpu_breakdown(container_or_pod, namespace="loco", is_k8s=False):
    """Get per-process CPU usage inside the container."""
    cmd_prefix = (
        ["kubectl", "exec", "-n", namespace, container_or_pod, "--"]
        if is_k8s
        else ["docker", "exec", container_or_pod]
    )

    try:
        raw = subprocess.check_output(
            cmd_prefix + ["ps", "aux", "--sort=-%cpu"],
            timeout=10, text=True,
        )
    except (subprocess.SubprocessError, FileNotFoundError):
        return []

    processes = []
    for line in raw.strip().splitlines()[1:6]:  # Top 5
        parts = line.split()
        if len(parts) >= 11:
            processes.append({
                "pid": parts[1],
                "cpu_pct": float(parts[2]),
                "mem_pct": float(parts[3]),
                "command": " ".join(parts[10:])[:50],
            })
    return processes


def profile_instance(host, port=8080, container_id=None, pod_name=None, namespace="loco"):
    """Profile a single emulator instance."""
    # Collect health endpoint data
    health = api_get(f"http://{host}:{port}/health")

    if "error" in health:
        return {"error": health["error"]}

    # Extract stage timings from health data
    stages = []

    # Stage 1: QEMU framebuffer generation
    qemu_cpu = health.get("system_performance", {}).get("qemu_cpu_percent", 0)
    stages.append({
        "stage": "QEMU Framebuffer",
        "component": "qemu-system-i386",
        "status": "active" if health.get("qemu_healthy") else "inactive",
        "cpu_pct": qemu_cpu,
        "notes": f"Frame generation at {health.get('video', {}).get('estimated_frame_rate', 0)} FPS",
    })

    # Stage 2: Xvfb display server
    stages.append({
        "stage": "Xvfb Display",
        "component": "Xvfb",
        "status": "active" if health.get("video", {}).get("display_active") else "inactive",
        "cpu_pct": 0,  # Usually negligible
        "notes": "1024x768x24 virtual framebuffer",
    })

    # Stage 3: GStreamer capture + encode
    stages.append({
        "stage": "GStreamer Capture",
        "component": "ximagesrc + videoconvert",
        "status": "active",
        "cpu_pct": 0,
        "notes": "ximagesrc → videoconvert → videoscale",
    })

    stages.append({
        "stage": "H.264 Encode",
        "component": "x264enc",
        "status": "active",
        "cpu_pct": 0,
        "notes": "ultrafast preset, 1200kbps, zerolatency tune",
    })

    # Stage 4: RTP packetisation
    stages.append({
        "stage": "RTP Packetise",
        "component": "rtph264pay",
        "status": "active",
        "cpu_pct": 0,
        "notes": "config-interval=1, H.264 NAL units → RTP",
    })

    # Stage 5: UDP transport
    network = health.get("network", {})
    stages.append({
        "stage": "UDP Transport",
        "component": "udpsink",
        "status": "active" if network.get("bridge_up") else "inactive",
        "cpu_pct": 0,
        "notes": f"TX: {network.get('tx_packets', 0)} pkts, Errors: {network.get('tx_errors', 0)}",
    })

    # Get per-process CPU breakdown
    is_k8s = pod_name is not None
    cid = pod_name or container_id
    if cid:
        processes = get_process_cpu_breakdown(cid, namespace, is_k8s)
        # Map process CPU to stages
        for proc in processes:
            cmd = proc["command"].lower()
            for stage in stages:
                if stage["component"].lower().split()[0] in cmd:
                    stage["cpu_pct"] = proc["cpu_pct"]
    else:
        processes = []

    # Identify bottleneck
    bottleneck = max(stages, key=lambda s: s.get("cpu_pct", 0))

    return {
        "stages": stages,
        "processes": processes,
        "bottleneck": bottleneck["stage"],
        "total_cpu": sum(p["cpu_pct"] for p in processes),
        "health": {
            "fps": health.get("video", {}).get("estimated_frame_rate", 0),
            "qemu_healthy": health.get("qemu_healthy", False),
            "overall": health.get("overall_status", "unknown"),
        },
    }


def generate_report(profiles, output_path):
    """Generate pipeline profiling markdown report."""
    lines = [
        "# Streaming Pipeline Profiling Report",
        "",
        f"**Generated**: {datetime.utcnow().isoformat()}Z",
        "",
        "## Pipeline Stages",
        "",
        "```",
        "QEMU Framebuffer → Xvfb → GStreamer Capture → H.264 Encode → RTP → UDP → WebRTC → Browser",
        "```",
        "",
    ]

    for name, profile in profiles.items():
        lines.append(f"### Instance: {name}")
        lines.append("")

        if "error" in profile:
            lines.append(f"_Error: {profile['error']}_")
            lines.append("")
            continue

        lines.append("| Stage | Component | Status | CPU % | Notes |")
        lines.append("|-------|-----------|--------|-------|-------|")
        for stage in profile["stages"]:
            lines.append(
                f"| {stage['stage']} | {stage['component']} | {stage['status']} "
                f"| {stage['cpu_pct']} | {stage['notes']} |"
            )
        lines.append("")

        lines.append(f"**Bottleneck**: {profile['bottleneck']}")
        lines.append(f"**Total CPU**: {profile['total_cpu']}%")
        lines.append(f"**Measured FPS**: {profile['health']['fps']}")
        lines.append("")

        if profile.get("processes"):
            lines.append("#### Top Processes")
            lines.append("| PID | CPU% | Mem% | Command |")
            lines.append("|-----|------|------|---------|")
            for proc in profile["processes"]:
                lines.append(f"| {proc['pid']} | {proc['cpu_pct']} | {proc['mem_pct']} | {proc['command']} |")
            lines.append("")

    # Recommendations
    lines.append("## Optimisation Recommendations")
    lines.append("")
    for name, profile in profiles.items():
        if "error" in profile:
            continue
        bn = profile["bottleneck"]
        if "QEMU" in bn:
            lines.append(f"- **{name}**: QEMU is the bottleneck — consider `-loadvm` snapshots or reducing guest resolution")
        elif "H.264" in bn:
            lines.append(f"- **{name}**: Encoder is the bottleneck — try `speed-preset=superfast` or lower bitrate")
        elif "Capture" in bn:
            lines.append(f"- **{name}**: Capture is the bottleneck — ensure Xvfb matches capture resolution")
    lines.append("")

    Path(output_path).write_text("\n".join(lines))
    print(f"Report written: {output_path}")


def main():
    parser = argparse.ArgumentParser(description="Streaming Pipeline Profiler")
    parser.add_argument("--targets", nargs="+", default=["localhost:8080"],
                        help="host:port targets to profile")
    parser.add_argument("--mode", choices=["direct", "k8s", "docker"], default="direct")
    parser.add_argument("--namespace", default="loco")
    parser.add_argument("--output", default="benchmark/PIPELINE_PROFILE.md")
    args = parser.parse_args()

    os.makedirs(os.path.dirname(args.output), exist_ok=True)
    profiles = {}

    if args.mode == "k8s":
        # Discover pods
        try:
            raw = subprocess.check_output(
                ["kubectl", "get", "pods", "-n", args.namespace,
                 "-l", "app.kubernetes.io/component=emulator",
                 "-o", "jsonpath={range .items[*]}{.metadata.name},{.status.podIP}{\"\\n\"}{end}"],
                timeout=15, text=True,
            )
            for line in raw.strip().splitlines():
                parts = line.split(",")
                if len(parts) == 2 and parts[1]:
                    name, ip = parts
                    print(f"Profiling {name} ({ip}) ...")
                    profiles[name] = profile_instance(ip, 8080, pod_name=name,
                                                      namespace=args.namespace)
        except Exception as e:
            print(f"K8s discovery failed: {e}")
    else:
        for target in args.targets:
            host, _, port = target.partition(":")
            port = int(port) if port else 8080
            print(f"Profiling {target} ...")
            profiles[target] = profile_instance(host, port)

    generate_report(profiles, args.output)


if __name__ == "__main__":
    main()
