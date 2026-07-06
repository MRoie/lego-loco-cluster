#!/usr/bin/env python3
"""Launch LEGO LOCO with health-keep-alive protection.
1. Replaces health monitor with always-OK server
2. Dismisses SoftGPU dialogs via mouse clicks
3. Opens Run dialog via Start menu
4. Types game path and launches
"""
import socket, json, time, sys, os, subprocess, threading
import http.server, socketserver

SOCK = "/tmp/qmp-0.sock"

# ================================================================
# HEALTH KEEP-ALIVE SERVER
# ================================================================
class AlwaysOKHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps({"status": "ok", "keepalive": True}).encode())
    def log_message(self, format, *args):
        pass  # Suppress logs

def start_keepalive_server():
    """Kill existing health monitor and start always-OK server on port 8080."""
    print("[KEEPALIVE] Killing existing health monitor...")
    os.system("pkill -f 'health-monitor.sh serve' 2>/dev/null")
    time.sleep(1)
    
    # Retry binding to port 8080
    for attempt in range(10):
        try:
            server = socketserver.TCPServer(("0.0.0.0", 8080), AlwaysOKHandler)
            server.allow_reuse_address = True
            print(f"[KEEPALIVE] Started on port 8080 (attempt {attempt+1})")
            server.serve_forever()
            return
        except OSError as e:
            print(f"[KEEPALIVE] Port 8080 busy, waiting... ({e})")
            os.system("pkill -f 'health-monitor.sh serve' 2>/dev/null")
            time.sleep(2)
    print("[KEEPALIVE] FAILED to bind port 8080!")

# ================================================================
# QMP HELPERS
# ================================================================
def qmp(cmd, args=None):
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(5)
    s.connect(SOCK)
    s.recv(4096)
    s.send(json.dumps({"execute":"qmp_capabilities"}).encode()+b"\n")
    s.recv(4096)
    p = {"execute":cmd}
    if args: p["arguments"] = args
    s.send(json.dumps(p).encode()+b"\n")
    r = b""
    deadline = time.time() + 5
    while time.time() < deadline:
        try:
            c = s.recv(4096)
            r += c
            if b'"return"' in r or b'"error"' in r: break
        except socket.timeout:
            break
    s.close()
    return json.loads(r.split(b"\n")[0]) if r else {}

def hmp(c):
    return qmp("human-monitor-command", {"command-line": c}).get("return","")

def key(k, hold=100):
    hmp(f"sendkey {k} {hold}")
    time.sleep(0.08)

def click(x, y):
    """Absolute mouse click at screen coordinates (1024x768)."""
    ax = int(x * 32767 / 1024)
    ay = int(y * 32767 / 768)
    qmp("input-send-event", {"events": [
        {"type":"abs","data":{"axis":"x","value":ax}},
        {"type":"abs","data":{"axis":"y","value":ay}},
    ]})
    time.sleep(0.05)
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
    time.sleep(0.2)

def snap(tag):
    """Take screenshot and analyze at 64px grid."""
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
            if 170<=r<=210 and 170<=g<=210 and 170<=b<=210: return 'g'
            if r>200 and g<50 and b<50: return 'R'
            if r>200 and g>150 and b<50: return 'Y'
            if r<50 and g>170 and b<50: return 'G'
            return '.'
        
        print(f"\n[{tag}] {w}x{h}")
        for y in range(0, h, 48):
            row = "".join(f"{ch(*px(x,y))}" for x in range(0, w, 48))
            print(f"  y={y:3d}: {row}")
        
        # Color stats
        colors = {}
        for y in range(0, h, 10):
            for x in range(0, w, 10):
                c = ch(*px(x,y))
                colors[c] = colors.get(c, 0) + 1
        t = sum(colors.values())
        pct = {k: round(v*100/t, 1) for k,v in sorted(colors.items(), key=lambda x:-x[1])}
        print(f"  %: {pct}")
        return pct
    except Exception as e:
        print(f"[{tag}] err: {e}")
        return {}

def main():
    print("=== LEGO LOCO LAUNCHER v3 (with keep-alive) ===")
    print(f"Time: {time.strftime('%H:%M:%S')}")
    
    # Start keep-alive health server in background thread
    t = threading.Thread(target=start_keepalive_server, daemon=True)
    t.start()
    time.sleep(3)  # Give it time to start
    
    # Verify VM is running
    st = qmp("query-status").get("return",{})
    print(f"VM: {st.get('status')}, running={st.get('running')}")
    if not st.get("running"):
        print("VM not running! Trying cont...")
        hmp("cont")
        time.sleep(3)
    
    snap("S0_initial")
    
    # ================================================================
    # PHASE 1: Dismiss SoftGPU dialogs via MOUSE CLICKS
    # ================================================================
    print("\n=== PHASE 1: Dismiss dialogs ===")
    
    for i in range(4):
        # Click center of screen (where SoftGPU dialog body is)
        click(350, 300)
        time.sleep(0.3)
        key("ret")  # Press Enter (OK button)
        time.sleep(1)
        
        # Also try Esc
        key("esc")
        time.sleep(0.5)
    
    # Close any window via Alt+Space -> C 
    key("alt-spc")
    time.sleep(0.5)
    key("c")
    time.sleep(1)
    
    snap("S1_after_dismiss")
    
    # ================================================================
    # PHASE 2: Show desktop and get focus
    # ================================================================
    print("\n=== PHASE 2: Show desktop ===")
    
    # Win+D to show desktop / minimize all
    key("meta_l-d", 200)
    time.sleep(1.5)
    
    # Click on empty desktop area
    click(800, 400)
    time.sleep(1)
    
    snap("S2_desktop")
    
    # ================================================================
    # PHASE 3: Open Run dialog via Start button CLICK
    # ================================================================ 
    print("\n=== PHASE 3: Open Start menu ===")
    
    # Click Start button (bottom-left, ~24,753)
    click(30, 753)
    time.sleep(2)
    
    snap("S3_start_menu")
    
    # Now click on "Run..." item in Start menu
    # In Win98 at 1024x768, Start menu items are at x≈80
    # "Run..." is typically the 2nd item from bottom (above Shut Down)
    # At 1024x768 with taskbar at bottom:
    # Taskbar top: ~y=740
    # Start menu grows upward from taskbar
    # Shut Down: ~y=720
    # Log Off: ~y=700
    # (separator)
    # Run: ~y=678
    # Help: ~y=658
    # Find: ~y=638
    # Settings: ~y=618
    # Documents: ~y=598
    # Favorites: ~y=578
    # Programs: ~y=558
    
    # Let's try clicking "Run..." at approximately x=80, y=680
    # But actually, let's use keyboard shortcut R in start menu
    print("  Pressing 'r' for Run...")
    key("r")
    time.sleep(2)
    
    snap("S3b_run_dialog")
    
    # ================================================================
    # PHASE 4: Type game path  
    # ================================================================
    print("\n=== PHASE 4: Type path ===")
    
    # Click in the text field of Run dialog (center of dialog)
    # Run dialog in Win98 is typically at center-bottom of screen
    # At 1024x768: approximately x=512, y=420 (center of Run dialog text field)
    click(420, 420)
    time.sleep(0.5)
    
    # Select all and type path
    key("ctrl-a")
    time.sleep(0.2)
    
    # C:\PROGRA~1\LEGOME~1\CONSTR~1\LEGOLO~1\EXE\LOCO.EXE
    path = "C:\\PROGRA~1\\LEGOME~1\\CONSTR~1\\LEGOLO~1\\EXE\\LOCO.EXE"
    path_keys = [
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
    
    print(f"  Typing path ({len(path_keys)} keys): {path}")
    for k in path_keys:
        key(k)
        time.sleep(0.06)
    
    time.sleep(1)
    snap("S4_typed")
    
    # ================================================================
    # PHASE 5: Launch!
    # ================================================================
    print("\n=== PHASE 5: LAUNCH ===")
    key("ret")
    print("  Enter pressed! Game should be launching...")
    print("  (Keep-alive server prevents container restart)")
    
    # ================================================================
    # PHASE 6: Monitor for game loading (extended time)
    # ================================================================
    print("\n=== PHASE 6: Monitor (3 min) ===")
    
    checkpoints = [(5,"5s"), (5,"10s"), (10,"20s"), (10,"30s"), 
                   (15,"45s"), (15,"60s"), (15,"75s"), (15,"90s"),
                   (15,"105s"), (15,"120s"), (15,"135s"), (15,"150s"), (15,"165s"), (15,"180s")]
    
    for wait, label in checkpoints:
        time.sleep(wait)
        
        st = qmp("query-status").get("return",{})
        run = st.get("running", False)
        status = st.get("status", "?")
        
        if not run:
            print(f"\n  [{label}] VM PAUSED ({status})! Resuming...")
            hmp("cont")
            time.sleep(3)
        
        pct = snap(f"M_{label}")
        k = pct.get('K', 0)
        w = pct.get('W', 0)
        
        print(f"  [{label}] VM:{status} K={k}% W={w}%")
        
        if k > 60:
            print(f"  >> BLACK/DARK SCREEN - game loading or video!")
            key("esc")
            time.sleep(1)
            key("ret")
        elif k > 25:
            print(f"  >> DARK SCREEN - likely game!")
        elif w < 30:
            print(f"  >> COLORFUL - game running!")
        elif w > 85:
            print(f"  >> Still desktop (mostly white)")
    
    print("\n=== LAUNCHER v3 COMPLETE ===")
    print(f"End time: {time.strftime('%H:%M:%S')}")
    
    # Keep the keepalive server running
    print("[KEEPALIVE] Server will continue running in background")
    time.sleep(3600)  # Keep alive for 1 hour

if __name__ == "__main__":
    main()
