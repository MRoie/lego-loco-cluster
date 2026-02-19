#!/usr/bin/env python3
"""LEGO LOCO Full Launch Pipeline: dismiss SoftGPU dialog, then Win+R to launch game.
Takes screenshots at every step."""
import socket, json, time

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
    time.sleep(0.08)

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
            f.readline()  # maxval
            data = f.read()
        
        def px(x, y):
            off = (y * w + x) * 3
            if off + 2 < len(data):
                return data[off], data[off+1], data[off+2]
            return (0,0,0)
        
        def c(r, g, b):
            if r > 240 and g > 240 and b > 240: return 'W'
            if r < 15 and g < 15 and b < 15: return 'K'
            if r < 20 and g > 100 and b > 100: return 'T'  # teal desktop
            if r < 20 and g < 60 and b > 100: return 'B'   # blue title bar
            if 180 <= r <= 200 and 180 <= g <= 200 and 180 <= b <= 200: return 'g'  # gray
            if 120 <= r <= 135 and 120 <= g <= 135 and 120 <= b <= 135: return 'd'  # dark gray
            if 210 <= r <= 230 and 210 <= g <= 230 and 210 <= b <= 230: return 'l'  # light gray
            if r > 200 and g < 50 and b < 50: return 'R'  # red
            if r > 200 and g > 150 and b < 50: return 'Y'  # yellow
            if r < 50 and g > 170 and b < 50: return 'G'  # green
            if r > 150 and g > 100 and b < 80: return 'O'  # orange/brown
            return '?'
        
        print(f"\n[{tag}] {w}x{h}")
        # Coarse grid every 64px
        header = "     " + "".join(f"{x:4d}" for x in range(0, w, 64))
        print(header)
        for y in range(0, h, 48):
            row = f"y={y:3d} " + "".join(f"   {c(*px(x,y))}" for x in range(0, w, 64))
            print(row)
        
        # Count colors
        colors = {}
        for y in range(0, h, 16):
            for x in range(0, w, 16):
                ch = c(*px(x, y))
                colors[ch] = colors.get(ch, 0) + 1
        total = sum(colors.values())
        print(f"  Colors: {', '.join(f'{k}={v*100//total}%' for k,v in sorted(colors.items(), key=lambda x:-x[1]))}")
        return colors
    except Exception as e:
        print(f"[{tag}] Error: {e}")
        return {}

def vm_status():
    s = qmp("query-status")
    st = s.get("return", {})
    return st.get("status","unknown"), st.get("running", False)

def main():
    print("=== LEGO LOCO Full Launch Pipeline ===")
    
    st, running = vm_status()
    print(f"VM: {st}, running={running}")
    if not running:
        print("VM not running! Resetting...")
        hmp("system_reset")
        time.sleep(1)
        hmp("cont")  
        print("Waiting 45s for boot...")
        time.sleep(45)
    
    # Step 1: See what's on screen
    c0 = screenshot_grid("1_initial")
    
    # Step 2: Dismiss SoftGPU dialog(s) with Enter, then Esc
    print("\n--- Step 2: Dismiss SoftGPU dialog ---")
    # Try Enter first (clicks OK on focused button)
    sendkey("ret")
    time.sleep(1)
    # Press Enter again in case there's a second dialog  
    sendkey("ret")
    time.sleep(1)
    # Press Esc to close any remaining dialog
    sendkey("esc")
    time.sleep(1)
    sendkey("esc")
    time.sleep(1)
    
    c1 = screenshot_grid("2_dismissed")
    
    # Check if desktop appeared (teal should be visible)
    teal_pct = c1.get('T', 0) * 100 // max(sum(c1.values()), 1)
    print(f"  Teal desktop: {teal_pct}%")
    
    if teal_pct < 5:
        print("  Desktop not visible yet, trying more dismissal...")
        for _ in range(3):
            sendkey("ret")
            time.sleep(0.5)
        for _ in range(3):
            sendkey("esc")
            time.sleep(0.5)
        time.sleep(2)
        c1b = screenshot_grid("2b_extra_dismiss")
    
    # Step 3: Win+R to open Run dialog
    print("\n--- Step 3: Win+R to open Run dialog ---")
    sendkey("meta_l-r", 200)
    time.sleep(2)
    c2 = screenshot_grid("3_run_dialog")
    
    # Step 4: Type game path
    print("\n--- Step 4: Type game path ---")
    sendkey("ctrl-a")  # select all existing text
    time.sleep(0.2)
    
    # Type: C:\PROGRA~1\LEGOME~1\CONSTR~1\LEGOLO~1\EXE\LOCO.EXE
    keys = [
        'shift-c', 'shift-semicolon', 'backslash',           # C:\
        'shift-p', 'shift-r', 'shift-o', 'shift-g', 'shift-r', 'shift-a',  # PROGRA
        'shift-grave_accent', '1', 'backslash',                # ~1\
        'shift-l', 'shift-e', 'shift-g', 'shift-o', 'shift-m', 'shift-e',  # LEGOME
        'shift-grave_accent', '1', 'backslash',                # ~1\
        'shift-c', 'shift-o', 'shift-n', 'shift-s', 'shift-t', 'shift-r',  # CONSTR
        'shift-grave_accent', '1', 'backslash',                # ~1\
        'shift-l', 'shift-e', 'shift-g', 'shift-o', 'shift-l', 'shift-o',  # LEGOLO
        'shift-grave_accent', '1', 'backslash',                # ~1\
        'shift-e', 'shift-x', 'shift-e', 'backslash',          # EXE\
        'shift-l', 'shift-o', 'shift-c', 'shift-o',            # LOCO
        'dot',                                                  # .
        'shift-e', 'shift-x', 'shift-e',                       # EXE
    ]
    for k in keys:
        sendkey(k)
        time.sleep(0.05)
    
    time.sleep(0.5)
    c3 = screenshot_grid("4_typed")
    
    # Step 5: Press Enter to launch
    print("\n--- Step 5: Launch! ---")
    sendkey("ret")
    
    # Step 6: Monitor launch with screenshots
    print("\n--- Step 6: Monitoring launch ---")
    for wait, label in [(3, "3s"), (5, "8s"), (5, "13s"), (7, "20s"), (10, "30s"), (15, "45s"), (15, "60s")]:
        time.sleep(wait)
        st, running = vm_status()
        print(f"\n  [{label}] VM: {st}, running={running}")
        if not running:
            print("  VM stopped! Game may have caused display mode change. Resuming...")
            hmp("cont")
            time.sleep(2)
        cn = screenshot_grid(f"5_{label}")
        
        # Check for game-typical colors (LEGO LOCO has yellow/green/bright colors)
        # Black screen could mean game is loading or display mode changed
        black_pct = cn.get('K', 0) * 100 // max(sum(cn.values()), 1)
        if black_pct > 80:
            print(f"  Screen is {black_pct}% black - could be game loading or mode change")
    
    print("\n=== PIPELINE COMPLETE ===")

if __name__ == "__main__":
    main()
