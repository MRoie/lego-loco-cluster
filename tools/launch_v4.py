#!/usr/bin/env python3
"""LEGO LOCO Launcher v4 - NEVER press Enter during SoftGPU dismiss.
Root cause found: Enter on SoftGPU's restart dialog reboots Win98.
Use only Esc and mouse clicks until the Run dialog is open."""
import socket, json, time, threading, http.server, socketserver, os, sys

SOCK = "/tmp/qmp-0.sock"

class OKHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(b'{"status":"ok"}')
    def log_message(self, *a): pass

def keepalive():
    os.system("pkill -f 'health-monitor.sh serve' 2>/dev/null")
    for _ in range(20):
        try:
            s = socketserver.TCPServer(("0.0.0.0", 8080), OKHandler)
            s.allow_reuse_address = True
            print("[KA] Bound 8080")
            s.serve_forever()
        except:
            os.system("pkill -f 'health-monitor.sh serve' 2>/dev/null")
            time.sleep(2)

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
        except: break
    s.close()
    return json.loads(r.split(b"\n")[0]) if r else {}

def hmp(c): return qmp("human-monitor-command",{"command-line":c}).get("return","")
def key(k, hold=100):
    hmp(f"sendkey {k} {hold}")
    time.sleep(0.08)

def click(x, y):
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
    hmp(f"screendump /tmp/ss_{tag}.ppm")
    time.sleep(0.3)
    try:
        with open(f"/tmp/ss_{tag}.ppm","rb") as f:
            f.readline()
            l = f.readline().strip()
            while l.startswith(b"#"): l = f.readline().strip()
            w,h = map(int, l.split())
            f.readline()
            d = f.read()
        def px(x,y):
            o = (y*w+x)*3
            return (d[o],d[o+1],d[o+2]) if o+2<len(d) else (0,0,0)
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
        for y in range(0,h,48):
            row="".join(f"{ch(*px(x,y))}" for x in range(0,w,48))
            print(f"  y={y:3d}: {row}")
        colors={}
        for y in range(0,h,10):
            for x in range(0,w,10):
                c=ch(*px(x,y))
                colors[c]=colors.get(c,0)+1
        t=sum(colors.values())
        pct={k:round(v*100/t,1) for k,v in sorted(colors.items(),key=lambda x:-x[1])}
        print(f"  %: {pct}")
        return pct
    except Exception as e:
        print(f"[{tag}] err: {e}")
        return {}

def main():
    print("=== LEGO LOCO LAUNCHER v4 ===")
    print(f"Time: {time.strftime('%H:%M:%S')}")
    threading.Thread(target=keepalive, daemon=True).start()
    time.sleep(3)
    
    st = qmp("query-status").get("return",{})
    print(f"VM: {st.get('status')}, running={st.get('running')}")
    if not st.get("running"):
        hmp("cont")
        time.sleep(3)
    
    snap("P0_initial")
    
    # ================================================================
    # PHASE 1: Dismiss SoftGPU WITHOUT pressing Enter
    # Use ONLY Esc and window close (Alt+Space→C)
    # NEVER press Enter - it triggers "Restart Now" which reboots Win98!
    # ================================================================
    print("\n=== PHASE 1: Dismiss SoftGPU (ESC ONLY - NO ENTER!) ===")
    
    for i in range(5):
        # Click on dialog to focus it
        click(350, 280)
        time.sleep(0.3)
        # Press Esc to cancel/close
        key("esc")
        time.sleep(0.8)
    
    snap("P1a_esc")
    
    # Close any remaining window via system menu
    for i in range(3):
        key("alt-spc")
        time.sleep(0.4)
        key("c")
        time.sleep(0.8)
    
    snap("P1b_closed")
    
    # ================================================================
    # PHASE 2: Minimize everything and focus desktop
    # ================================================================
    print("\n=== PHASE 2: Show desktop ===")
    
    # Win+M to minimize all windows
    key("meta_l-m", 200)
    time.sleep(1.5)
    
    # Win+D to show desktop
    key("meta_l-d", 200)
    time.sleep(1.5)
    
    # Click empty desktop
    click(800, 400)
    time.sleep(0.5)
    click(600, 500)
    time.sleep(0.5)
    
    snap("P2_desktop")
    
    # ================================================================
    # PHASE 3: Open Run dialog with Win+R
    # ================================================================
    print("\n=== PHASE 3: Win+R ===")
    
    key("meta_l-r", 300)
    time.sleep(3)
    
    pct = snap("P3_winr")
    
    # Verify Run dialog appeared - should see some gray (dialog body)
    g = pct.get('g', 0) + pct.get('B', 0)
    if g < 1:
        print("  Run dialog may not have appeared. Trying again...")
        click(800, 400)
        time.sleep(0.5)
        key("meta_l-r", 400)
        time.sleep(3)
        snap("P3b_retry")
    
    # ================================================================
    # PHASE 4: Type game path - FIRST press Enter HERE (in Run dialog)
    # ================================================================
    print("\n=== PHASE 4: Type path ===")
    
    # Click in Run dialog text field (center of screen where dialog should be)
    # Win98 Run dialog: ~400px wide, centered at ~512,420
    click(450, 420)
    time.sleep(0.5)
    
    key("ctrl-a")
    time.sleep(0.2)
    
    # Type: C:\PROGRA~1\LEGOME~1\CONSTR~1\LEGOLO~1\EXE\LOCO.EXE
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
    
    print(f"  Typing {len(path_keys)} keys...")
    for k in path_keys:
        key(k)
        time.sleep(0.06)
    
    time.sleep(1)
    snap("P4_typed")
    
    # ================================================================
    # PHASE 5: Launch! (FIRST safe Enter press)
    # ================================================================
    print("\n=== PHASE 5: LAUNCH ===")
    key("ret")
    print("  Enter pressed in Run dialog!")
    
    # ================================================================
    # PHASE 6: Monitor
    # ================================================================
    print("\n=== PHASE 6: Monitor (3 min) ===")
    
    for wait, label in [(5,"5s"),(5,"10s"),(10,"20s"),(10,"30s"),
                        (15,"45s"),(15,"60s"),(15,"75s"),(15,"90s"),
                        (15,"105s"),(15,"120s"),(15,"135s"),(15,"150s"),
                        (15,"165s"),(15,"180s")]:
        time.sleep(wait)
        st = qmp("query-status").get("return",{})
        run = st.get("running", False)
        status = st.get("status", "?")
        if not run:
            print(f"\n  [{label}] VM PAUSED! Resuming...")
            hmp("cont")
            time.sleep(3)
        pct = snap(f"M_{label}")
        k = pct.get('K', 0)
        w = pct.get('W', 0)
        r = pct.get('R', 0)
        y = pct.get('Y', 0)
        print(f"  [{label}] VM:{status} K={k}% W={w}% R={r}% Y={y}%")
        if k > 50:
            print("  >> BLACK - game loading/video!")
            key("esc")
            time.sleep(1)
            key("spc")
        elif k > 20 or r > 5 or y > 5:
            print("  >> GAME DETECTED! (dark/colorful)")
        elif w < 50:
            print("  >> COLORFUL - game running!")
        else:
            print("  >> Desktop still visible")
    
    print("\n=== LAUNCHER v4 COMPLETE ===")
    time.sleep(3600)

if __name__ == "__main__":
    main()
