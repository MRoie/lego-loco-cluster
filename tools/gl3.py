#!/usr/bin/env python3
"""Game launcher v3: handle SoftGPU dialog, use proven Start>Up>Up>Enter for Run."""
import json, socket, time, os

LOG = '/tmp/gl3.txt'

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
    def click(self, x, y, delay=0.3):
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
            cats = {'W':0,'B':0,'G':0,'T':0,'O':0}
            for y in range(0, h, 8):
                for x in range(0, w, 8):
                    i = (y*w+x)*3
                    if i+2 >= len(data): continue
                    r,g,b = data[i], data[i+1], data[i+2]
                    if r>220 and g>220 and b>220: cats['W'] += 1
                    elif r<30 and g<30 and b<30: cats['B'] += 1
                    elif 180<r<230 and abs(r-g)<10 and abs(r-b)<10: cats['G'] += 1
                    elif r<50 and g>90 and b>90 and abs(g-b)<30: cats['T'] += 1
                    else: cats['O'] += 1
            t = max(sum(cats.values()), 1)
            log("%s: W=%d%% B=%d%% G=%d%% T=%d%% O=%d%%" % (
                label, cats['W']*100//t, cats['B']*100//t,
                cats['G']*100//t, cats['T']*100//t,
                cats['O']*100//t))
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
    
    # 1. See current state
    q.snap("S0_initial")
    
    # 2. Dismiss the SoftGPU white window aggressively
    # Try multiple methods: Esc, Enter, Tab+Enter, Alt+F4, clicking corners
    log("dismissing white dialog...")
    
    # Method 1: Press Esc several times
    for _ in range(3):
        q.k('esc', 0.3)
    
    # Method 2: Press Enter (OK button)
    q.k('ret', 0.5)
    
    # Method 3: Alt+F4 to close window
    q.k('alt-f4', 0.5)
    
    # Method 4: If SoftGPU has "Next" button, it's probably center-bottom
    # Try clicking potential buttons: OK, Next, Cancel
    # SoftGPU installer buttons might be at specific positions
    q.click(512, 520, 0.5)  # center-bottom area
    q.k('ret', 0.5)
    q.k('alt-f4', 0.5)
    
    # Method 5: Windows sometimes has "Welcome" screen - try close button
    q.click(989, 5, 0.3)  # top-right close button (1024-35, 5)
    q.k('alt-f4', 0.5)
    
    time.sleep(1)
    q.snap("S1_after_dismiss")
    
    # 3. Check if we see desktop (teal) or still white
    # If still mostly white, try more dismissal
    q.k('alt-f4', 0.5)
    q.k('alt-f4', 0.5)
    q.click(512, 400, 0.5)
    q.k('esc', 0.5)
    
    q.snap("S2_cleared")
    
    # 4. Click on desktop teal area to ensure desktop has focus
    # Desktop is visible at (50,50) = teal
    q.click(30, 30, 1.0)
    
    # 5. Open Run dialog using PROVEN method: Ctrl+Esc (Start), Up, Up, Enter
    log("opening Run via Start>Up>Up>Enter...")
    q.k('ctrl-esc', 1.5)
    q.snap("S3_start_menu")
    
    q.k('up', 0.3)
    q.k('up', 0.3)
    q.k('ret', 2.0)
    q.snap("S4_run_dialog")
    
    # 6. Clear field and type path
    q.k('ctrl-a', 0.2)
    q.k('delete', 0.3)
    
    # Type: c:\progra~1\legome~1\constr~1\legolo~1\exe\loco.exe
    # Using lowercase - Windows paths are case-insensitive
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
    
    log("typing %d keys..." % len(path_keys))
    for k in path_keys:
        q.h('sendkey %s 50' % k)
        time.sleep(0.04)
    time.sleep(0.5)
    q.snap("S5_path_typed")
    
    # 7. Press Enter to launch
    log("pressing Enter...")
    q.k('ret', 1.0)
    
    # 8. Monitor: take screenshots at intervals
    for sec in [3, 5, 10, 15, 20, 30]:
        if sec <= 3:
            time.sleep(sec)
        else:
            time.sleep(sec - 3)
        q.snap("S6_t%ds" % sec)
    
    # 9. Try to dismiss intro videos
    log("attempting video dismiss...")
    for _ in range(3):
        q.k('esc', 1.5)
    q.click(512, 384, 2.0)
    q.snap("S7_after_video_dismiss")
    
    q.s.close()
    log("DONE")

if __name__ == '__main__':
    main()
