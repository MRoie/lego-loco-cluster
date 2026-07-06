#!/usr/bin/env python3
"""Clean LEGO LOCO launch: dismiss SoftGPU, Win+R, type path, Enter.
No Start menu - only Win+R."""
import socket, json, time

SOCK = "/tmp/qmp-0.sock"

def qmp(cmd, args=None):
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.connect(SOCK)
    s.recv(4096)
    s.send(json.dumps({"execute":"qmp_capabilities"}).encode()+b"\n")
    s.recv(4096)
    p = {"execute":cmd}
    if args: p["arguments"] = args
    s.send(json.dumps(p).encode()+b"\n")
    r = b""
    while True:
        c = s.recv(4096)
        r += c
        if b'"return"' in r or b'"error"' in r: break
    s.close()
    return json.loads(r.split(b"\n")[0])

def hmp(c):
    return qmp("human-monitor-command", {"command-line": c}).get("return","")

def key(k, hold=100):
    hmp(f"sendkey {k} {hold}")
    time.sleep(0.08)

def click(x, y):
    """Absolute mouse click."""
    ax = int(x * 32767 / 1024)
    ay = int(y * 32767 / 768)
    qmp("input-send-event", {"events": [
        {"type":"abs","data":{"axis":"x","value":ax}},
        {"type":"abs","data":{"axis":"y","value":ay}},
        {"type":"btn","data":{"button":"left","down":True}}
    ]})
    time.sleep(0.1)
    qmp("input-send-event", {"events": [
        {"type":"abs","data":{"axis":"x","value":ax}},
        {"type":"abs","data":{"axis":"y","value":ay}},
        {"type":"btn","data":{"button":"left","down":False}}
    ]})
    time.sleep(0.15)

def snap(tag):
    """Take screenshot and analyze."""
    hmp(f"screendump /tmp/ss_{tag}.ppm")
    time.sleep(0.3)
    try:
        with open(f"/tmp/ss_{tag}.ppm", "rb") as f:
            f.readline()
            line = f.readline().strip()
            while line.startswith(b"#"): line = f.readline().strip()
            w, h = map(int, line.split())
            f.readline()
            data = f.read()
        
        def px(x, y):
            o = (y*w+x)*3
            return (data[o], data[o+1], data[o+2]) if o+2 < len(data) else (0,0,0)
        
        def ch(r,g,b):
            if r>240 and g>240 and b>240: return 'W'
            if r<15 and g<15 and b<15: return 'K'
            if r<20 and g>100 and b>100: return 'T'
            if r<20 and g<80 and b>100: return 'B'
            if 180<=r<=200 and 180<=g<=200 and 180<=b<=200: return 'g'
            if r>200 and g<50 and b<50: return 'R'
            if r>200 and g>150 and b<50: return 'Y'
            if r<50 and g>170 and b<50: return 'G'
            return '.'
        
        print(f"\n[{tag}] {w}x{h}")
        for y in range(0, h, 64):
            row = "".join(f" {ch(*px(x,y))}" for x in range(0, w, 64))
            print(f"  y={y:3d}:{row}")
        
        colors = {}
        for y in range(0, h, 20):
            for x in range(0, w, 20):
                c = ch(*px(x,y))
                colors[c] = colors.get(c, 0) + 1
        t = sum(colors.values())
        pct = {k: v*100//t for k,v in colors.items()}
        print(f"  %: {pct}")
        return pct
    except Exception as e:
        print(f"[{tag}] err: {e}")
        return {}

def main():
    print("=== CLEAN LEGO LOCO LAUNCH ===")
    st = qmp("query-status").get("return",{})
    print(f"VM: {st.get('status')}, run={st.get('running')}")
    
    snap("0_boot")
    
    # Phase 1: Dismiss SoftGPU dialog(s) aggressively
    print("\n--- Phase 1: Dismiss SoftGPU ---")
    # Enter to click OK on focused dialog button
    for i in range(5):
        key("ret")
        time.sleep(0.8)
    # Esc to close anything remaining  
    for i in range(3):
        key("esc")
        time.sleep(0.5)
    
    time.sleep(2)
    p1 = snap("1_dismissed")
    
    # Phase 2: Click on empty desktop area to ensure desktop has focus
    print("\n--- Phase 2: Focus desktop ---")
    click(700, 400)  # Click empty area (right side of screen)
    time.sleep(1)
    snap("2_desktop_focus")
    
    # Phase 3: Win+R to open Run dialog
    print("\n--- Phase 3: Win+R ---")
    key("meta_l-r", 200)
    time.sleep(2)
    p3 = snap("3_winr")
    
    # Check if Run dialog appeared (look for gray increase)
    if p3.get('g', 0) > 3:
        print("  Run dialog likely appeared!")
    else:
        print("  Run dialog may not have appeared, trying again...")
        key("esc")
        time.sleep(0.5)
        click(700, 400)
        time.sleep(1)
        key("meta_l-r", 300)
        time.sleep(2)
        snap("3b_winr_retry")
    
    # Phase 4: Type the game path
    print("\n--- Phase 4: Type game path ---")
    key("ctrl-a")  # Select all existing text
    time.sleep(0.2)
    
    # C:\PROGRA~1\LEGOME~1\CONSTR~1\LEGOLO~1\EXE\LOCO.EXE
    path_keys = [
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
    for k in path_keys:
        key(k)
        time.sleep(0.04)
    
    time.sleep(1)
    snap("4_typed")
    
    # Phase 5: Press Enter to launch
    print("\n--- Phase 5: LAUNCH ---")
    key("ret")
    
    # Phase 6: Monitor
    print("\n--- Phase 6: Monitoring ---")
    for wait, label in [(5, "5s"), (10, "15s"), (15, "30s"), (20, "50s"), (20, "70s")]:
        time.sleep(wait)
        st = qmp("query-status").get("return",{})
        run = st.get("running", False)
        status = st.get("status", "?")
        print(f"\n  [{label}] VM: {status}, running={run}")
        if not run:
            print("  VM paused! Resuming...")
            hmp("cont")
            time.sleep(3)
        pn = snap(f"5_{label}")
        
        # Detect game: black loading screen or colorful game screen
        k_pct = pn.get('K', 0)
        w_pct = pn.get('W', 0)
        if k_pct > 50:
            print(f"  >> DARK SCREEN ({k_pct}% black) - game may be loading!")
        elif w_pct < 50:
            print(f"  >> Screen changed significantly (only {w_pct}% white) - something happened!")
    
    print("\n=== LAUNCH COMPLETE ===")

if __name__ == "__main__":
    main()
