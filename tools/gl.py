#!/usr/bin/env python3
"""Simple focused launcher: close all, open Run, launch game."""
import json, socket, time, os

LOG = '/tmp/gl.txt'

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
            cats = {'W':0,'B':0,'G':0,'BL':0,'O':0}
            for y in range(0, h, 6):
                for x in range(0, w, 6):
                    i = (y*w+x)*3
                    if i+2 >= len(data): continue
                    r,g,b = data[i], data[i+1], data[i+2]
                    if r>220 and g>220 and b>220: cats['W'] += 1
                    elif r<30 and g<30 and b<30: cats['B'] += 1
                    elif 180<r<230 and abs(r-g)<10 and abs(r-b)<10: cats['G'] += 1
                    elif b>100 and r<80 and g<80: cats['BL'] += 1
                    else: cats['O'] += 1
            t = max(sum(cats.values()), 1)
            # Also check for specific game indicators:
            # Green grass = high g, low r/b
            # Intro video = mostly dark
            green = 0
            teal = 0
            for y in range(0, h, 10):
                for x in range(0, w, 10):
                    i = (y*w+x)*3
                    if i+2 >= len(data): continue
                    r,g,b = data[i], data[i+1], data[i+2]
                    if g > 120 and g > r+30 and g > b+30: green += 1
                    if g > 100 and b > 100 and r < 80: teal += 1
            gt = h//10 * w//10 or 1
            log("%s: W=%d%% B=%d%% G=%d%% BL=%d%% O=%d%% green=%d%% teal=%d%%" % (
                label, cats['W']*100//t, cats['B']*100//t,
                cats['G']*100//t, cats['BL']*100//t,
                cats['O']*100//t, green*100//gt, teal*100//gt))
            # Sample key positions
            samples = []
            for py in [50, h//4, h//2, 3*h//4, h-50]:
                for px in [50, w//4, w//2, 3*w//4, w-50]:
                    i = (py*w+px)*3
                    if i+2 < len(data):
                        samples.append((px,py,data[i],data[i+1],data[i+2]))
            log("  samples: %s" % str(samples[:8]))
            return w, h, data
        except Exception as e:
            log("snap err: %s" % e)
            return 0, 0, b''

def log(msg):
    with open(LOG, 'a') as f:
        f.write("%s\n" % msg)

def main():
    iid = int(os.environ.get('INSTANCE_ID', '0'))
    open(LOG, 'w').close()
    log("START id=%d" % iid)
    
    q = Q('/tmp/qmp-%d.sock' % iid)
    log("connected")
    
    # 1. Current state
    q.snap("S0_initial")
    
    # 2. Close ALL windows aggressively
    log("closing all windows...")
    for i in range(8):
        q.k('alt-f4', 0.5)
    time.sleep(1)
    q.snap("S1_cleared")
    
    # 3. Click desktop to ensure focus
    q.h('mouse_move 512 400')
    time.sleep(0.1)
    q.h('mouse_button 1')
    time.sleep(0.1)
    q.h('mouse_button 0')
    time.sleep(0.5)
    
    # 4. Open Run dialog via Ctrl+Esc (Start), then R key
    # Ctrl+Esc opens Start Menu, then 'r' should select Run
    log("opening Start menu...")
    q.k('ctrl-esc', 1.5)
    q.snap("S2_start_menu")
    
    # In Win98, the Run... item is near the top when going from bottom
    # Standard Win98 Start menu order (bottom to top):
    # Shut Down, Run, Help, Find, Settings, Documents, Programs
    # So Up once = Run (or we press 'R' as accelerator)
    log("selecting Run...")
    q.k('r', 2.0)
    q.snap("S3_run_dialog")
    
    # 5. Clear and type path
    q.k('ctrl-a', 0.2)
    q.k('delete', 0.3)
    
    # Type: C:\PROGRA~1\LEGOME~1\CONSTR~1\LEGOLO~1\EXE\LOCO.EXE
    # Using lowercase since Windows paths are case-insensitive
    path_keys = [
        'c', 'shift-semicolon', 'backslash',  # c:\
        'p','r','o','g','r','a',  # progra
        'shift-grave_accent', '1', 'backslash',  # ~1\
        'l','e','g','o','m','e',  # legome
        'shift-grave_accent', '1', 'backslash',  # ~1\
        'c','o','n','s','t','r',  # constr
        'shift-grave_accent', '1', 'backslash',  # ~1\
        'l','e','g','o','l','o',  # legolo
        'shift-grave_accent', '1', 'backslash',  # ~1\
        'e','x','e', 'backslash',  # exe\
        'l','o','c','o',  # loco
        'dot',  # .
        'e','x','e',  # exe
    ]
    
    log("typing path (%d keys)..." % len(path_keys))
    for k in path_keys:
        q.h('sendkey %s 50' % k)
        time.sleep(0.04)
    time.sleep(0.5)
    q.snap("S4_path_typed")
    
    # 6. Press Enter to launch
    log("pressing Enter...")
    q.k('ret', 3.0)
    q.snap("S5_after_enter_3s")
    
    time.sleep(5)
    q.snap("S6_after_8s")
    
    time.sleep(7)
    q.snap("S7_after_15s")
    
    time.sleep(15)
    q.snap("S8_after_30s")
    
    # 7. Try Esc to dismiss intro videos
    log("esc for videos...")
    for i in range(3):
        q.k('esc', 2.0)
    q.snap("S9_after_esc")
    
    # 8. Click center to dismiss splash
    q.h('mouse_move 512 384')
    time.sleep(0.1)
    q.h('mouse_button 1')
    time.sleep(0.1)
    q.h('mouse_button 0')
    time.sleep(2)
    q.snap("S10_after_click")
    
    q.s.close()
    log("DONE")

if __name__ == '__main__':
    main()
