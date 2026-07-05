#!/usr/bin/env python3
"""Launch LEGO LOCO via Win+R Run dialog. Takes screenshots at each step."""
import socket, json, time, struct

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

def sendkey(keys, hold=100):
    hmp(f"sendkey {keys} {hold}")

def screenshot_analysis(tag):
    """Take screenshot, analyze key regions, return summary."""
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
            maxval = int(f.readline().strip())
            data = f.read()
        
        def px(x, y):
            off = (y * w + x) * 3
            if off + 2 < len(data):
                return data[off], data[off+1], data[off+2]
            return (0,0,0)
        
        # Color classification
        def classify(r, g, b):
            if r > 240 and g > 240 and b > 240: return 'W'
            if r < 15 and g < 15 and b < 15: return 'K'
            if g > 200 and r < 50 and b < 50: return 'G'  # green
            if r > 200 and g < 50 and b < 50: return 'R'  # red
            if r < 50 and g < 50 and b > 200: return 'B'  # blue
            if r < 20 and g > 100 and b > 100: return 'T'  # teal (desktop)
            if 180 <= r <= 200 and 180 <= g <= 200 and 180 <= b <= 200: return 'g'  # gray UI
            if 120 <= r <= 135 and 120 <= g <= 135 and 120 <= b <= 135: return 'd'  # dark gray
            if 210 <= r <= 230 and 210 <= g <= 230 and 210 <= b <= 230: return 'l'  # light gray
            return '?'
        
        # Grid every 50px
        print(f"\n[{tag}] {w}x{h}")
        print("    " + "".join(f"{x:5d}" for x in range(0, w, 50)))
        for y in range(0, h, 50):
            row = ""
            for x in range(0, w, 50):
                c = classify(*px(x, y))
                row += f"    {c}"
            print(f"y={y:3d}" + row)
        
        # Check center for Run dialog (typically ~400x200 centered)
        # Run dialog in Win98 is about 347x162 at center
        cx, cy = w//2, h//2
        center_colors = {}
        for dy in range(-100, 101, 20):
            for dx in range(-200, 201, 20):
                c = classify(*px(cx+dx, cy+dy))
                center_colors[c] = center_colors.get(c, 0) + 1
        print(f"  Center area: {center_colors}")
        
        # Check if there's a gray dialog box (Run dialog has gray background)
        # Look for a gray rectangle in the center area
        gray_at_center = 0
        for dy in range(-80, 81, 10):
            for dx in range(-170, 171, 10):
                r, g, b = px(cx+dx, cy+dy)
                if 180 <= r <= 200 and 180 <= g <= 200 and 180 <= b <= 200:
                    gray_at_center += 1
        print(f"  Gray pixels in center dialog area: {gray_at_center}")
        
    except Exception as e:
        print(f"[{tag}] Screenshot error: {e}")

def type_text(text):
    """Type text using QEMU sendkey, handling special chars."""
    keymap = {
        ':': 'shift-semicolon',
        '\\': 'backslash',
        '/': 'slash',
        '.': 'dot',
        ' ': 'spc',
        '~': 'shift-grave_accent',
        '-': 'minus',
        '_': 'shift-minus',
        '1': '1', '2': '2', '3': '3', '4': '4', '5': '5',
        '6': '6', '7': '7', '8': '8', '9': '9', '0': '0',
    }
    for ch in text:
        if ch in keymap:
            sendkey(keymap[ch])
        elif ch.isupper():
            sendkey(f"shift-{ch.lower()}")
        elif ch.islower():
            sendkey(ch)
        time.sleep(0.05)

def main():
    print("=== LEGO LOCO Launcher via Win+R ===")
    
    # Step 0: Check VM status
    status = qmp("query-status")
    print(f"VM status: {status.get('return', {}).get('status', 'unknown')}")
    running = status.get('return', {}).get('running', False)
    if not running:
        print("VM not running! Resetting...")
        hmp("system_reset")
        time.sleep(1)
        hmp("cont")
        print("Waiting 30s for boot...")
        time.sleep(30)
    
    # Step 1: Take baseline screenshot
    screenshot_analysis("S0_before")
    
    # Step 2: Press Escape a few times to dismiss any dialogs/menus
    print("\n--- Dismissing any open dialogs (Esc x3) ---")
    for i in range(3):
        sendkey("esc")
        time.sleep(0.3)
    time.sleep(0.5)
    screenshot_analysis("S1_cleared")
    
    # Step 3: Press Win+R to open Run dialog
    print("\n--- Sending Win+R (meta_l-r) ---")
    sendkey("meta_l-r", 200)
    time.sleep(1.5)
    screenshot_analysis("S2_run_dialog")
    
    # Step 4: Clear any existing text in Run dialog (Ctrl+A then type)
    print("\n--- Clearing text field (Ctrl+A) ---")
    sendkey("ctrl-a")
    time.sleep(0.2)
    
    # Step 5: Type the game path
    # C:\PROGRA~1\LEGOME~1\CONSTR~1\LEGOLO~1\EXE\LOCO.EXE
    game_path = "C:\\PROGRA~1\\LEGOME~1\\CONSTR~1\\LEGOLO~1\\EXE\\LOCO.EXE"
    print(f"\n--- Typing: {game_path} ---")
    
    # Type character by character
    # C : \ P R O G R A ~ 1 \ ...
    chars = [
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
        'shift-l', 'shift-o', 'shift-c', 'shift-o', 'dot',
        'shift-e', 'shift-x', 'shift-e',
    ]
    for k in chars:
        sendkey(k)
        time.sleep(0.06)
    
    time.sleep(0.5)
    screenshot_analysis("S3_typed")
    
    # Step 6: Press Enter to execute
    print("\n--- Pressing Enter to launch ---")
    sendkey("ret")
    
    # Step 7: Take screenshots over time to monitor launch
    for wait, label in [(2, "t2s"), (3, "t5s"), (5, "t10s"), (10, "t20s"), (10, "t30s")]:
        time.sleep(wait)
        screenshot_analysis(f"S4_{label}")
    
    print("\n=== LAUNCH SEQUENCE COMPLETE ===")

if __name__ == "__main__":
    main()
