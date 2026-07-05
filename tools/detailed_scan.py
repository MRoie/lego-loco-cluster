#!/usr/bin/env python3
"""Detailed screen scan - find UI elements, buttons, text areas."""
import socket, json, struct, time

SOCK = "/tmp/qmp-0.sock"

def qmp(cmd, args=None):
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.connect(SOCK)
    s.recv(4096)
    s.send(json.dumps({"execute":"qmp_capabilities"}).encode()+b"\n")
    s.recv(4096)
    payload = {"execute":cmd}
    if args: payload["arguments"] = args
    s.send(json.dumps(payload).encode()+b"\n")
    r = b""
    while True:
        chunk = s.recv(4096)
        r += chunk
        if b'"return"' in r or b'"error"' in r:
            break
    s.close()
    return json.loads(r.split(b"\n")[0])

def hmp(cmd_str):
    r = qmp("human-monitor-command", {"command-line": cmd_str})
    return r.get("return","")

def screenshot(path="/tmp/scan.ppm"):
    hmp(f"screendump {path}")
    time.sleep(0.3)

def read_ppm(path="/tmp/scan.ppm"):
    with open(path, "rb") as f:
        magic = f.readline().strip()  # P6
        line = f.readline().strip()
        while line.startswith(b"#"):
            line = f.readline().strip()
        w, h = map(int, line.split())
        maxval = int(f.readline().strip())
        data = f.read()
    return w, h, data

def get_pixel(data, w, x, y):
    off = (y * w + x) * 3
    return data[off], data[off+1], data[off+2]

def scan():
    screenshot()
    w, h, data = read_ppm()
    print(f"Resolution: {w}x{h}")
    
    # 1) Fine grid around y=90-120 (where variation was seen)
    print("\n=== DETAIL: y=80-130, every 10px, x every 50px ===")
    for y in range(80, 131, 10):
        row = []
        for x in range(0, w, 50):
            r, g, b = get_pixel(data, w, x, y)
            row.append(f"({r},{g},{b})")
        print(f"  y={y:3d}: {' '.join(row)}")
    
    # 2) Fine grid of top-left corner (title bar area)
    print("\n=== TOP-LEFT 200x30 every 10px ===")
    for y in range(0, 31, 5):
        row = []
        for x in range(0, 201, 10):
            r, g, b = get_pixel(data, w, x, y)
            row.append(f"({r},{g},{b})")
        print(f"  y={y:3d}: {' '.join(row)}")
    
    # 3) Scan every 20px for non-white regions
    print("\n=== NON-WHITE REGIONS (every 20px) ===")
    for y in range(0, h, 20):
        for x in range(0, w, 20):
            r, g, b = get_pixel(data, w, x, y)
            if r < 240 or g < 240 or b < 240:
                print(f"  ({x:4d},{y:3d}): ({r},{g},{b})")
    
    # 4) Look for button-like regions (gray ~192,192,192 or ~189,189,189)
    print("\n=== POSSIBLE BUTTONS (gray blobs, every 10px) ===")
    for y in range(0, h-50, 10):
        for x in range(0, w, 10):
            r, g, b = get_pixel(data, w, x, y)
            if 180 <= r <= 200 and 180 <= g <= 200 and 180 <= b <= 200:
                print(f"  ({x:4d},{y:3d}): ({r},{g},{b})")
    
    # 5) Taskbar detail
    print("\n=== TASKBAR y=740-768, every 5px ===")
    for y in range(740, min(h, 769), 2):
        row = []
        for x in range(0, min(w, 200), 10):
            r, g, b = get_pixel(data, w, x, y)
            row.append(f"({r},{g},{b})")
        print(f"  y={y:3d}: {' '.join(row)}")
    
    # 6) Look for the center of the screen for any dialog
    print("\n=== CENTER REGION 400-600x300-500, every 20px ===")
    for y in range(300, 501, 20):
        row = []
        for x in range(400, 601, 20):
            r, g, b = get_pixel(data, w, x, y)
            row.append(f"({r},{g},{b})")
        print(f"  y={y:3d}: {' '.join(row)}")

    print("\nDONE")

if __name__ == "__main__":
    scan()
