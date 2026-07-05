#!/usr/bin/env python3
"""
SAFE game launcher - NO Alt+F4 (causes Win98 shutdown!)
Uses only Esc and Enter for dialog dismissal.
"""
import json, socket, time, os

LOG = '/tmp/safe_launch.txt'

class Q:
    def __init__(self, path):
        self.s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.s.settimeout(10)
        self.s.connect(path)
        self.buf = b''
        self._r()
        self.c('qmp_capabilities')
    def _r(self):
        while True:
            nl = self.buf.find(b'\n')
            if nl >= 0:
                line = self.buf[:nl]; self.buf = self.buf[nl+1:]
                if line.strip():
                    try: return json.loads(line)
                    except: pass
                continue
            try:
                d = self.s.recv(4096)
                if not d: return {}
                self.buf += d
            except socket.timeout: return {}
    def c(self, ex, args=None):
        m = {'execute': ex}
        if args: m['arguments'] = args
        self.s.sendall(json.dumps(m).encode() + b'\n')
        for _ in range(20):
            r = self._r()
            if 'return' in r or 'error' in r: return r
        return {}
    def h(self, cmd):
        return self.c('human-monitor-command', {'command-line': cmd})
    def k(self, name, delay=0.3):
        self.h('sendkey %s 100' % name)
        time.sleep(delay)
    def click(self, x, y, delay=0.5):
        self.h('mouse_move %d %d' % (x, y))
        time.sleep(0.1)
        self.h('mouse_button 1')
        time.sleep(0.1)
        self.h('mouse_button 0')
        time.sleep(delay)
    def snap(self, label):
        self.c('screendump', {'filename': '/tmp/ss.ppm'})
        time.sleep(0.5)
        try:
            with open('/tmp/ss.ppm', 'rb') as f:
                f.readline()
                line = f.readline()
                while line.startswith(b'#'): line = f.readline()
                w, h = map(int, line.split())
                f.readline()
                data = f.read()
            W = B = G = T = O = 0
            for y in range(0, h, 8):
                for x in range(0, w, 8):
                    i = (y*w+x)*3
                    if i+2 >= len(data): continue
                    r,g,b = data[i], data[i+1], data[i+2]
                    if r>220 and g>220 and b>220: W += 1
                    elif r<30 and g<30 and b<30: B += 1
                    elif 180<r<230 and abs(r-g)<10 and abs(r-b)<10: G += 1
                    elif r<50 and g>90 and b>90 and abs(g-b)<30: T += 1
                    else: O += 1
            t = max(W+B+G+T+O, 1)
            log("%s: W=%d%% B=%d%% G=%d%% T=%d%% O=%d%%" % (
                label, W*100//t, B*100//t, G*100//t, T*100//t, O*100//t))
            return w, h, data, {'W':W*100//t,'B':B*100//t,'T':T*100//t}
        except Exception as e:
            log("snap err: %s" % e)
            return 0, 0, b'', {}

def log(msg):
    with open(LOG, 'a') as f:
        f.write("%s\n" % msg)

def safe_dismiss(q):
    """SAFE dialog dismissal - only Esc and Enter, NEVER Alt+F4."""
    log("safe dismiss (no alt+f4)...")
    
    # Round 1: Just Esc — closes most dialogs safely
    for i in range(5):
        q.k('esc', 0.4)
    time.sleep(1)
    
    # Round 2: Enter — clicks OK/default button
    q.k('ret', 1.0)
    
    # Round 3: More Esc
    for i in range(3):
        q.k('esc', 0.4)
    time.sleep(0.5)
    
    # Round 4: Tab+Enter — moves to next button then clicks
    q.k('tab', 0.2)
    q.k('ret', 1.0)
    
    # Round 5: Click center of screen and Esc
    q.click(512, 400, 0.5)
    q.k('esc', 0.5)

def main():
    iid = int(os.environ.get('INSTANCE_ID', '0'))
    open(LOG, 'w').close()
    log("=== SAFE LAUNCH id=%d ===" % iid)
    
    q = Q('/tmp/qmp-%d.sock' % iid)
    log("connected")
    
    # Step 1: Initial screenshot
    w, h, d, cats = q.snap("S0")
    
    # Step 2: Safe dismiss
    safe_dismiss(q)
    w, h, d, cats = q.snap("S1_dismissed")
    
    # Step 3: If still mostly white, do another round
    if cats.get('W', 0) > 50:
        log("still white, trying again...")
        safe_dismiss(q)
        w, h, d, cats = q.snap("S1b_dismissed")
    
    # Step 4: Check for teal desktop
    if cats.get('T', 0) > 10:
        log("teal desktop visible!")
    elif cats.get('B', 0) > 80:
        log("WARNING: screen is black - VM may have shutdown!")
        return
    
    # Step 5: Click on desktop area (left edge where teal was seen at x=50)
    log("clicking desktop...")
    q.click(20, 400, 1.0)
    
    # Step 6: Open Run dialog via PROVEN method
    log("opening Run: Ctrl+Esc > Up > Up > Enter")
    q.k('ctrl-esc', 1.5)
    w, h, d, cats = q.snap("S2_startmenu")
    
    q.k('up', 0.3)
    q.k('up', 0.3)
    q.k('ret', 2.0)
    w, h, d, cats = q.snap("S3_run")
    
    # Step 7: If Run dialog opened (more gray pixels), type the path
    log("clearing and typing path...")
    q.k('ctrl-a', 0.2)
    q.k('delete', 0.3)
    
    # Path: c:\progra~1\legome~1\constr~1\legolo~1\exe\loco.exe
    path_keys = [
        'c', 'shift-semicolon', 'backslash',
        'p','r','o','g','r','a',
        'shift-grave_accent', '1', 'backslash',
        'l','e','g','o','m','e',
        'shift-grave_accent', '1', 'backslash',
        'c','o','n','s','t','r',
        'shift-grave_accent', '1', 'backslash',
        'l','e','g','o','l','o',
        'shift-grave_accent', '1', 'backslash',
        'e','x','e', 'backslash',
        'l','o','c','o',
        'dot',
        'e','x','e',
    ]
    
    log("typing %d keys..." % len(path_keys))
    for k in path_keys:
        q.h('sendkey %s 50' % k)
        time.sleep(0.04)
    time.sleep(0.5)
    w, h, d, cats = q.snap("S4_typed")
    
    # Step 8: LAUNCH
    log("ENTER to launch!")
    q.k('ret', 1.0)
    
    # Step 9: Monitor
    for sec in [3, 8, 15, 25, 40]:
        prev = 0
        if sec == 3:
            time.sleep(3)
        else:
            time.sleep(sec - prev)
        prev = sec
        w, h, d, cats = q.snap("S5_t%ds" % sec)
    
    # Step 10: Try to skip intro videos
    log("trying to skip videos...")
    q.k('esc', 2.0)
    q.k('esc', 2.0) 
    q.click(512, 384, 2.0)
    q.k('esc', 2.0)
    w, h, d, cats = q.snap("S6_after_skip")
    
    time.sleep(10)
    w, h, d, cats = q.snap("S7_final")
    
    q.s.close()
    log("=== DONE ===")

if __name__ == '__main__':
    main()
