#!/usr/bin/env python3
"""Launch LEGO LOCO using mouse clicks for reliable navigation.
Uses QMP input-send-event for absolute mouse positioning."""
import socket, json, time

SOCK = "/tmp/qmp-0.sock"
W, H = 1024, 768  # Screen resolution

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

def sendkey(keys, hold=100):
    hmp(f"sendkey {keys} {hold}")
    time.sleep(0.08)

def mouse_click(x, y, button="left"):
    """Click at absolute pixel coordinates using QMP input-send-event."""
    # Convert pixel coords to absolute (0-32767)
    ax = int(x * 32767 / W)
    ay = int(y * 32767 / H)
    
    # Move mouse to position + click down
    events = [
        {"type": "abs", "data": {"axis": "x", "value": ax}},
        {"type": "abs", "data": {"axis": "y", "value": ay}},
        {"type": "btn", "data": {"button": button, "down": True}}
    ]
    qmp("input-send-event", {"events": events})
    time.sleep(0.1)
    
    # Release button
    events2 = [
        {"type": "abs", "data": {"axis": "x", "value": ax}},
        {"type": "abs", "data": {"axis": "y", "value": ay}},
        {"type": "btn", "data": {"button": button, "down": False}}
    ]
    qmp("input-send-event", {"events": events2})
    time.sleep(0.15)

def mouse_dblclick(x, y):
    """Double-click at absolute pixel coordinates."""
    mouse_click(x, y)
    time.sleep(0.05)
    mouse_click(x, y)

def screenshot_grid(tag):
    """Quick screenshot with character grid."""
    path = f"/tmp/ss_{tag}.ppm"
    hmp(f"screendump {path}")
    time.sleep(0.3)
    try:
        with open(path, "rb") as f:
            magic = f.readline().strip()
            line = f.readline().strip()
            while line.startswith(b"#"):
                line = f.readline().strip()
            w, h = map(int, line.split())
            f.readline()
            data = f.read()
        
        def px(x, y):
            off = (y * w + x) * 3
            if off + 2 < len(data):
                return data[off], data[off+1], data[off+2]
            return (0,0,0)
        
        def c(r, g, b):
            if r > 240 and g > 240 and b > 240: return 'W'
            if r < 15 and g < 15 and b < 15: return 'K'
            if r < 20 and g > 100 and b > 100: return 'T'
            if r < 20 and g < 80 and b > 100: return 'B'
            if 180 <= r <= 200 and 180 <= g <= 200 and 180 <= b <= 200: return 'g'
            if 120 <= r <= 135 and 120 <= g <= 135 and 120 <= b <= 135: return 'd'
            if 210 <= r <= 230 and 210 <= g <= 230 and 210 <= b <= 230: return 'l'
            if r > 200 and g < 50 and b < 50: return 'R'
            if r > 200 and g > 150 and b < 50: return 'Y'
            if r < 50 and g > 170 and b < 50: return 'G'
            return '?'
        
        print(f"\n[{tag}] {w}x{h}")
        header = "     " + "".join(f"{x:4d}" for x in range(0, w, 64))
        print(header)
        for y in range(0, h, 48):
            row = f"y={y:3d} " + "".join(f"   {c(*px(x,y))}" for x in range(0, w, 64))
            print(row)
        
        colors = {}
        for y in range(0, h, 16):
            for x in range(0, w, 16):
                ch = c(*px(x, y))
                colors[ch] = colors.get(ch, 0) + 1
        total = sum(colors.values())
        pcts = ', '.join(f'{k}={v*100//total}%' for k,v in sorted(colors.items(), key=lambda x:-x[1]))
        print(f"  Colors: {pcts}")
        
        # Check specific regions
        # Taskbar presence (gray at bottom)
        tb_gray = 0
        for x in range(0, w, 20):
            r, g, b = px(x, h-10)
            if 180 <= r <= 200 and 180 <= g <= 200 and 180 <= b <= 200:
                tb_gray += 1
        print(f"  Taskbar gray pixels: {tb_gray}/{w//20}")
        
        return colors
    except Exception as e:
        print(f"[{tag}] Error: {e}")
        return {}

def main():
    print("=== LEGO LOCO Mouse-Based Launch ===")
    
    # Check VM
    st = qmp("query-status").get("return", {})
    print(f"VM: {st.get('status','?')}, running={st.get('running',False)}")
    if not st.get("running"):
        hmp("system_reset"); time.sleep(1); hmp("cont")
        print("Reset+resumed, waiting 45s..."); time.sleep(45)
    
    # Step 1: Initial screenshot
    screenshot_grid("M0_initial")
    
    # Step 2: Dismiss SoftGPU dialogs by clicking OK buttons
    # The SoftGPU dialog on Win98 typically has an OK button
    # Let's try clicking in different possible OK button positions
    print("\n--- Step 2: Dismiss dialogs via mouse + keys ---")
    
    # First try Enter to dismiss any focused dialog
    sendkey("ret")
    time.sleep(1.5)
    screenshot_grid("M1_after_enter1")
    
    # Now there might be a second dialog. Let's try clicking its Close button (X)
    # The blue title bar at ~y=336, x=320-448 in previous scans
    # The X button would be at the right end of the title bar
    # Let's try clicking various positions
    
    # Try Enter again
    sendkey("ret")
    time.sleep(1)
    
    # Try Esc
    sendkey("esc")
    time.sleep(1)
    
    # Try clicking on empty desktop area to close/deactivate dialog
    mouse_click(800, 400)
    time.sleep(0.5)
    
    screenshot_grid("M2_after_clicks")
    
    # Step 3: Now try to get to desktop and open Run
    # First, minimize all with Win+M
    print("\n--- Step 3: Minimize all (Win+M) ---")
    sendkey("meta_l-m", 200)
    time.sleep(1)
    screenshot_grid("M3_winm")
    
    # Step 4: Try Win+R
    print("\n--- Step 4: Win+R ---")
    sendkey("meta_l-r", 200)
    time.sleep(1.5)
    screenshot_grid("M4_winr")
    
    # Step 5: If Win+R didn't work, try mouse on Start button
    # Try Ctrl+Esc as backup 
    print("\n--- Step 5: Ctrl+Esc (Start menu) ---")
    sendkey("ctrl-esc")
    time.sleep(1)
    screenshot_grid("M5_start")
    
    # Click on Run... item in Start menu
    # In Win98 @ 1024x768, Start menu opens above the Start button
    # Run is typically the 3rd item from bottom
    # Start button: ~x=30, y=753
    # Each menu item is ~22px high
    # Shut Down: y ~= 741 (bottom)
    # Log Off: y ~= 719
    # Run: y ~= 697
    # Help: y ~= 675
    print("\n--- Step 5b: Click on Run menu item ---")
    mouse_click(80, 697)
    time.sleep(1.5)
    screenshot_grid("M6_run_clicked")
    
    # Step 6: Type path
    print("\n--- Step 6: Clear and type game path ---")
    sendkey("ctrl-a")
    time.sleep(0.2)
    
    keys = [
        'shift-c', 'shift-semicolon', 'backslash',
        'shift-p', 'shift-r', 'shift-o', 'shift-g', 'shift-r', 'shift-a',
        'shift-grave_accent', '1', 'backslash',
        'shift-l', 'shift-e', 'shift-g', 'shift-o', 'shift-m', 'shift-e',
        'shift-grave_accent', '1', 'backslash',
        'shift-c', 'shift-o', 'shift-n', 'shift-s', 'shift-t', 'shift-r',
        'shift-grave_accent', '1', 'backslash',
        'shift-l', 'shift-e', 'shift-g', 'shift-o', 'shift-l', 'shift-o',
        'shift-grave_accent', '1', 'backslash',
        'shift-e', 'shift-x', 'shift-e', 'backslash',
        'shift-l', 'shift-o', 'shift-c', 'shift-o',
        'dot',
        'shift-e', 'shift-x', 'shift-e',
    ]
    for k in keys:
        sendkey(k)
        time.sleep(0.04)
    
    time.sleep(0.5)
    screenshot_grid("M7_typed")
    
    # Step 7: Press Enter to launch
    print("\n--- Step 7: Launch! (Enter) ---")
    sendkey("ret")
    
    # Monitor
    for wait, label in [(3, "3s"), (5, "8s"), (10, "18s"), (15, "33s"), (15, "48s")]:
        time.sleep(wait)
        st = qmp("query-status").get("return", {})
        running = st.get("running", False)
        print(f"\n  [{label}] VM: {st.get('status','?')}, running={running}")
        if not running:
            print("  VM stopped! Resuming...")
            hmp("cont")
            time.sleep(2)
        screenshot_grid(f"M8_{label}")
    
    print("\n=== DONE ===")

if __name__ == "__main__":
    main()
