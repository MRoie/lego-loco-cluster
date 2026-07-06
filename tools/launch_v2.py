#!/usr/bin/env python3
"""Robust LEGO LOCO launcher v2 - uses mouse clicks for everything.
Key insight: SoftGPU dialog doesn't have keyboard focus on fresh boot,
so Enter/Esc do nothing. Must click on dialog first."""
import socket, json, time, sys

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

def keys(seq, delay=0.04):
    """Send a sequence of keys."""
    for k in seq:
        key(k)
        time.sleep(delay)

def click(x, y, double=False):
    """Absolute mouse click at screen coordinates."""
    ax = int(x * 32767 / 1024)
    ay = int(y * 32767 / 768)
    # Move mouse
    qmp("input-send-event", {"events": [
        {"type":"abs","data":{"axis":"x","value":ax}},
        {"type":"abs","data":{"axis":"y","value":ay}},
    ]})
    time.sleep(0.05)
    # Click
    qmp("input-send-event", {"events": [
        {"type":"abs","data":{"axis":"x","value":ax}},
        {"type":"abs","data":{"axis":"y","value":ay}},
        {"type":"btn","data":{"button":"left","down":True}}
    ]})
    time.sleep(0.05)
    qmp("input-send-event", {"events": [
        {"type":"abs","data":{"axis":"x","value":ax}},
        {"type":"abs","data":{"axis":"y","value":ay}},
        {"type":"btn","data":{"button":"left","down":False}}
    ]})
    time.sleep(0.15)
    if double:
        time.sleep(0.1)
        qmp("input-send-event", {"events": [
            {"type":"abs","data":{"axis":"x","value":ax}},
            {"type":"abs","data":{"axis":"y","value":ay}},
            {"type":"btn","data":{"button":"left","down":True}}
        ]})
        time.sleep(0.05)
        qmp("input-send-event", {"events": [
            {"type":"abs","data":{"axis":"x","value":ax}},
            {"type":"abs","data":{"axis":"y","value":ay}},
            {"type":"btn","data":{"button":"left","down":False}}
        ]})
        time.sleep(0.15)

def snap(tag, detail=False):
    """Take screenshot and analyze. If detail=True, use 16px grid."""
    hmp(f"screendump /tmp/ss_{tag}.ppm")
    time.sleep(0.3)
    try:
        with open(f"/tmp/ss_{tag}.ppm", "rb") as f:
            f.readline()  # P6
            line = f.readline().strip()
            while line.startswith(b"#"): line = f.readline().strip()
            w, h = map(int, line.split())
            f.readline()  # 255
            data = f.read()
        
        def px(x, y):
            o = (y*w+x)*3
            return (data[o], data[o+1], data[o+2]) if o+2 < len(data) else (0,0,0)
        
        def ch(r,g,b):
            if r>240 and g>240 and b>240: return 'W'
            if r<15 and g<15 and b<15: return 'K'
            if r<20 and g>100 and b>100: return 'T'
            if r<20 and g<80 and b>100: return 'B'
            if 180<=r<=210 and 180<=g<=210 and 180<=b<=210: return 'g'
            if r>200 and g<50 and b<50: return 'R'
            if r>200 and g>150 and b<50: return 'Y'
            if r<50 and g>170 and b<50: return 'G'
            if 100<=r<=160 and 100<=g<=160 and 100<=b<=160: return 'd'  # dark gray
            return '.'
        
        step = 16 if detail else 64
        print(f"\n[{tag}] {w}x{h} (step={step})")
        for y in range(0, h, step):
            row = "".join(f"{ch(*px(x,y))}" for x in range(0, w, step))
            print(f"  y={y:3d}: {row}")
        
        # Color percentages
        colors = {}
        for y in range(0, h, 8):
            for x in range(0, w, 8):
                c = ch(*px(x,y))
                colors[c] = colors.get(c, 0) + 1
        t = sum(colors.values())
        pct = {k: round(v*100/t, 1) for k,v in sorted(colors.items(), key=lambda x:-x[1])}
        print(f"  %: {pct}")
        
        # High-interest areas (title bars, buttons, taskbar)
        if detail:
            print(f"  Taskbar area (y=740-767):")
            for y in [740, 748, 756, 764]:
                row = "".join(f"{ch(*px(x,y))}" for x in range(0, 128, 8))
                print(f"    y={y}: {row}")
        
        return pct, data, w, h
    except Exception as e:
        print(f"[{tag}] err: {e}")
        return {}, None, 0, 0

def find_dialog_buttons(data, w, h):
    """Try to find dialog buttons by looking for gray rectangles near bottom of content area."""
    def px(x, y):
        o = (y*w+x)*3
        return (data[o], data[o+1], data[o+2]) if o+2 < len(data) else (0,0,0)
    
    # Scan for horizontal gray bands (potential button rows)
    results = []
    for y in range(100, 500, 4):
        gray_count = 0
        button_start = None
        for x in range(100, 700, 4):
            r,g,b = px(x, y)
            is_gray = (170 <= r <= 210 and 170 <= g <= 210 and 170 <= b <= 210)
            if is_gray:
                if button_start is None:
                    button_start = x
                gray_count += 1
            else:
                if gray_count >= 10:  # At least 40px of gray
                    results.append((button_start, y, x, gray_count))
                button_start = None
                gray_count = 0
    
    return results

def main():
    print("=== LEGO LOCO LAUNCHER v2 (Mouse-Based) ===")
    print(f"Time: {time.strftime('%H:%M:%S')}")
    
    st = qmp("query-status").get("return",{})
    print(f"VM: {st.get('status')}, running={st.get('running')}")
    if not st.get("running"):
        print("VM not running! Trying cont...")
        hmp("cont")
        time.sleep(3)
    
    # ================================================================
    # PHASE 1: Understand current screen state
    # ================================================================
    print("\n" + "="*60)
    print("PHASE 1: Analyze initial screen")
    print("="*60)
    pct, data, w, h = snap("P1_initial", detail=True)
    
    # ================================================================
    # PHASE 2: Dismiss SoftGPU dialog(s) using MOUSE CLICKS
    # ================================================================
    print("\n" + "="*60)
    print("PHASE 2: Dismiss SoftGPU dialogs")
    print("="*60)
    
    # The SoftGPU dialog in the 0_boot screenshot appears at roughly:
    # x=128-512, y=128-448  (from the 64px grid analysis)
    # It likely has OK/Close buttons at the bottom of the dialog
    
    # Strategy: 
    # 1. Click ON the dialog body to give it focus
    # 2. Press Enter to click OK
    # 3. Check if it dismissed
    # 4. If there's a second dialog, repeat
    
    for attempt in range(5):
        print(f"\n  Dismiss attempt {attempt+1}:")
        
        # Click on center of likely dialog area to focus it
        click(320, 300)
        time.sleep(0.3)
        
        # Press Enter (should click focused OK button)
        key("ret")
        time.sleep(1.5)
        
        # Take screenshot to check
        pct2, _, _, _ = snap(f"P2_dismiss_{attempt}", detail=False)
        
        # Check if screen changed significantly (less gray = dialog gone)
        gray = pct2.get('g', 0) + pct2.get('d', 0)
        print(f"  Gray: {gray}%")
        if gray < 2:
            print("  Dialog appears dismissed!")
            break
    
    # Also try closing via Alt+Space -> C (system menu Close)
    # This is SAFE - it closes the active window, NOT the desktop
    print("\n  Trying Alt+Space -> C to close any remaining window...")
    key("alt-spc")
    time.sleep(0.5)
    key("c")
    time.sleep(1)
    snap("P2_after_close", detail=False)
    
    # ================================================================
    # PHASE 3: Ensure desktop has focus  
    # ================================================================
    print("\n" + "="*60)
    print("PHASE 3: Focus desktop")
    print("="*60)
    
    # Win+D to show desktop (minimizes all)
    key("meta_l-d", 200)
    time.sleep(1.5)
    
    # Click on empty area of desktop
    click(800, 500)
    time.sleep(0.5)
    
    snap("P3_desktop", detail=True)
    
    # ================================================================
    # PHASE 4: Open Start Menu and click Run
    # ================================================================
    print("\n" + "="*60)
    print("PHASE 4: Open Run dialog via Start Menu")
    print("="*60)
    
    # Click the Start button (bottom-left corner)
    # In 1024x768, Start button is at approximately x=24, y=753
    print("  Clicking Start button...")
    click(30, 753)
    time.sleep(1.5)
    
    snap("P4_start_menu", detail=True)
    
    # In Win98 Start menu, "Run..." should be near the bottom
    # Start menu items from bottom to top typically:
    # Shut Down... (~y=740)
    # Log Off... (~y=720)  
    # ... separator ...
    # Run... (~y=690)
    # Help (~y=670)
    # Find... (~y=650)
    # Settings... (~y=630)
    # Documents... (~y=610)
    # Favorites... (~y=590)
    # Programs... (~y=570)
    
    # Actually let's use keyboard: press 'r' to jump to Run
    # In Win98 Start menu, pressing a letter goes to matching item
    print("  Pressing R for Run...")
    key("r")
    time.sleep(1.5)
    
    snap("P4_run_dialog", detail=True)
    
    # ================================================================  
    # PHASE 5: Type game path in Run dialog
    # ================================================================
    print("\n" + "="*60)
    print("PHASE 5: Type game path")
    print("="*60)
    
    # Select any existing text first
    key("ctrl-a")
    time.sleep(0.2)
    
    # Type: C:\PROGRA~1\LEGOME~1\CONSTR~1\LEGOLO~1\EXE\LOCO.EXE
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
    
    print(f"  Typing {len(path_keys)} keys...")
    for k in path_keys:
        key(k)
        time.sleep(0.05)
    
    time.sleep(1)
    snap("P5_typed", detail=True)
    
    # ================================================================
    # PHASE 6: Launch!
    # ================================================================
    print("\n" + "="*60)
    print("PHASE 6: LAUNCH (pressing Enter)")
    print("="*60)
    
    key("ret")
    print("  Enter pressed! Waiting for game to load...")
    
    # ================================================================
    # PHASE 7: Monitor and handle dialogs
    # ================================================================
    print("\n" + "="*60)
    print("PHASE 7: Monitor game loading")
    print("="*60)
    
    for wait, label in [(3, "3s"), (5, "8s"), (7, "15s"), (10, "25s"), (15, "40s"), (15, "55s"), (15, "70s"), (15, "85s")]:
        time.sleep(wait)
        
        st = qmp("query-status").get("return",{})
        run = st.get("running", False)
        status = st.get("status", "?")
        
        if not run:
            print(f"\n  [{label}] VM PAUSED ({status})! Resuming...")
            hmp("cont")
            time.sleep(3)
            st = qmp("query-status").get("return",{})
            status = st.get("status", "?")
        
        pct, _, _, _ = snap(f"P7_{label}", detail=False)
        k = pct.get('K', 0)
        w_pct = pct.get('W', 0)
        g = pct.get('g', 0)
        t = pct.get('T', 0)
        
        print(f"  [{label}] VM:{status} K={k}% W={w_pct}% g={g}% T={t}%")
        
        # Detect game states:
        if k > 50:
            print(f"  >> BLACK SCREEN - game loading or video playing!")
            # Try pressing Esc/Enter to skip videos
            key("esc")
            time.sleep(0.5)
            key("ret")
        elif k > 20:
            print(f"  >> DARK SCREEN - likely game starting!")
        elif w_pct < 40:
            print(f"  >> COLORFUL SCREEN ({w_pct}% white) - game may be running!")
        elif g > 20:
            print(f"  >> GRAY DIALOG - may need dismissal")
            key("ret")
        else:
            print(f"  >> Mostly white desktop still")
    
    print("\n=== LAUNCHER v2 COMPLETE ===")
    print(f"Final time: {time.strftime('%H:%M:%S')}")

if __name__ == "__main__":
    main()
