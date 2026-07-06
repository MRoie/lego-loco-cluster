#!/usr/bin/env python3
import http.server
import socketserver
import json
import subprocess
import time
import os
import sys

PORT = 8080

def run_cmd(cmd):
    try:
        return subprocess.check_output(cmd, shell=True, stderr=subprocess.DEVNULL).decode('utf-8').strip()
    except:
        return ""

def get_qemu_health():
    pid = run_cmd("pgrep -f qemu-system-i386")
    return "true" if pid else "false"

def get_video_health():
    vnc_port = 5901
    vnc_available = "false"
    if run_cmd(f"netstat -ln | grep :{vnc_port}"):
        vnc_available = "true"
    
    display_active = "false"
    frame_rate = 0
    vnc_display = os.environ.get("VNC_DISPLAY", ":1")
    
    # Check X display
    if run_cmd(f"xdpyinfo -display {vnc_display}"):
        display_active = "true"
        # Estimate frame rate
        x_activity = run_cmd(f"xwininfo -display {vnc_display} -root -stats | grep -c 'window'")
        if x_activity and int(x_activity) > 0:
            frame_rate = 15

    return {
        "vnc_available": vnc_available == "true",
        "display_active": display_active == "true",
        "estimated_frame_rate": frame_rate,
        "vnc_port": vnc_port,
        "display": vnc_display
    }

def get_audio_health():
    pulse_running = "false"
    if run_cmd("pgrep pulseaudio"):
        pulse_running = "true"
    
    audio_devices = 0
    try:
        out = run_cmd("pactl list short sinks | wc -l")
        audio_devices = int(out) if out else 0
    except:
        pass

    alsa_devices = 0
    try:
        out = run_cmd("aplay -l | grep -c 'card '")
        alsa_devices = int(out) if out else 0
    except:
        pass

    return {
        "pulse_running": pulse_running == "true",
        "audio_devices": audio_devices,
        "alsa_devices": alsa_devices,
        "estimated_level": 0.5 if audio_devices > 0 else 0,
        "audio_backend": os.environ.get("AUDIO_DEVICE", "pulse")
    }

def get_system_performance():
    # cpu usage from top (simplified)
    cpu_usage = 0
    try:
        # top -bn1 | grep "Cpu(s)" | awk '{print $2}'
        out = run_cmd("top -bn1 | grep 'Cpu(s)' | awk '{print $2}' | cut -d'%' -f1")
        cpu_usage = float(out) if out else 0
    except:
        pass

    memory_usage = 0
    try:
        # free | grep Mem | awk '{printf "%.1f", $3/$2 * 100.0}'
        out = run_cmd("free | grep Mem | awk '{printf \"%.1f\", $3/$2 * 100.0}'")
        memory_usage = float(out) if out else 0
    except:
        pass

    load_average = 0
    try:
        out = run_cmd("uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | tr -d ','")
        load_average = float(out) if out else 0
    except:
        pass

    qemu_pid = run_cmd("pgrep -f qemu-system-i386")
    qemu_cpu = 0
    qemu_memory = 0
    if qemu_pid:
        try:
            qemu_cpu = float(run_cmd(f"ps -p {qemu_pid} -o %cpu --no-headers") or 0)
            qemu_memory = float(run_cmd(f"ps -p {qemu_pid} -o %mem --no-headers") or 0)
        except:
            pass

    return {
        "cpu_usage": cpu_usage,
        "memory_usage": memory_usage,
        "load_average": load_average,
        "qemu_cpu": qemu_cpu,
        "qemu_memory": qemu_memory,
        "qemu_pid": qemu_pid
    }

def get_network_health():
    bridge_up = bool(run_cmd("ip link show loco-br"))
    tap_up = bool(run_cmd("ip link show tap0"))
    
    def read_stat(path):
        try:
            with open(path, 'r') as f:
                return int(f.read().strip())
        except:
            return 0

    return {
        "bridge_up": bridge_up,
        "tap_up": tap_up,
        "tx_packets": read_stat("/sys/class/net/tap0/statistics/tx_packets"),
        "rx_packets": read_stat("/sys/class/net/tap0/statistics/rx_packets"),
        "tx_errors": read_stat("/sys/class/net/tap0/statistics/tx_errors"),
        "rx_errors": read_stat("/sys/class/net/tap0/statistics/rx_errors")
    }

class HealthHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        qemu_healthy = get_qemu_health()
        video_health = get_video_health()
        audio_health = get_audio_health()
        
        overall_status = "healthy"
        if qemu_healthy == "false":
            overall_status = "unhealthy"
        elif not video_health["vnc_available"]:
            overall_status = "degraded"
        elif not audio_health["pulse_running"]:
            overall_status = "degraded"

        report = {
            "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "overall_status": overall_status,
            "qemu_healthy": qemu_healthy == "true",
            "video": video_health,
            "audio": audio_health,
            "performance": get_system_performance(),
            "network": get_network_health()
        }
        
        response_bytes = json.dumps(report).encode('utf-8')
        
        self.send_response(200)
        self.send_header('Content-type', 'application/json')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Content-Length', str(len(response_bytes)))
        self.end_headers()
        self.wfile.write(response_bytes)

    def log_message(self, format, *args):
        pass

if __name__ == "__main__":
    print(f"Starting Python health server on port {PORT}")
    # Allow reuse address to avoid "Address already in use" on restart
    socketserver.TCPServer.allow_reuse_address = True
    with socketserver.TCPServer(("", PORT), HealthHandler) as httpd:
        httpd.serve_forever()
