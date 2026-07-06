#!/usr/bin/env python3
"""Focused game launcher: dismiss dialogs, launch LEGO LOCO, monitor."""
import json, socket, time, os

LOG = '/tmp/launch_log.txt'

class QMP:
    def __init__(self, path):
        self.s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.s.settimeout(10)
        self.s.connect(path)
        self.buf = b''
        self._read()
        self.cmd('qmp_capabilities')
    def _read(self):
        while True:
            nl = self.buf.find(b'\n')
            if nl >= 0:
                line = self.buf[:nl]
                self.buf = self.buf[nl+1:]
                if line.strip():
                    try: return json.loads(line)
                    except: pass
                continue
            try:
                c = self.s.recv(4096)
                if not c: return {}
                self.buf += c
            except socket.timeout: return {}
    def cmd(self, ex, args=None):
        m = {'execute': ex}
        if args: m['arguments'] = args
        self.s.sendall(json.dumps(m).encode() + b'\n')
        for _ in range(20):
            r = self._read()
            if 'return' in r or 'error' in r: return r
        return {}
    def hmp(self, c):
        return self.cmd('human-monitor-command', {'command-line': c})
    def key(self, name, delay=0.3):
        self.hmp('sendkey %s 100' % name)
        time.sleep(delay)
    def keys(self, names, delay=0.05):
        """Send multiple keys quickly."""
        for n in names:
            self.hmp('sendkey %s 50' % n)
            time.sleep(delay)
    def snap(self, label=""):
        path = '/tmp/ss.ppm'
        self.cmd('screendump', {'filename': path})
        time.sleep(0.5)
        try:
            with open(path, 'rb') as f:
                f.readline()  # P6
                line = f.readline()
                while line.startswith(b'#'): line = f.readline()
                w, h = map(int, line.split())
                f.readline()  # 255
                data = f.read()
            cats = {'W':0,'B':0,'G':0,'BL':0,'O':0}
            for y in range(0, h, 8):
                for x in range(0, w, 8):
                    i = (y*w+x)*3
                    if i+2 >= len(data): continue
                    r,g,b = data[i], data[i+1], data[i+2]
                    if r>220 and g>220 and b>220: cats['W'] += 1
                    elif r<30 and g<30 and b<30: cats['B'] += 1
                    elif 180<r<230 and abs(r-g)<10 and abs(r-b)<10: cats['G'] += 1
                    elif b>100 and r<80 and g<80: cats['BL'] += 1
                    else: cats['O'] += 1
            t = max(sum(cats.values()), 1)
            result = "W=%d%% B=%d%% G=%d%% BL=%d%% O=%d%%" % (
                cats['W']*100//t, cats['B']*100//t,
                cats['G']*100//t, cats['BL']*100//t,
                cats['O']*100//t)
            log("%s: %s" % (label, result))
            # Also sample specific regions
            # Desktop teal: ~0,128,128 or similar
            # Check if there's a large window (white/gray center)
            center_colors = []
            for cy in [h//4, h//2, 3*h//4]:
                for cx in [w//4, w//2, 3*w//4]:
                    i = (cy*w+cx)*3
                    if i+2 < len(data):
                        center_colors.append((data[i], data[i+1], data[i+2]))
            log("  center_samples: %s" % str(center_colors[:5]))
            return w, h, data
        except Exception as e:
            log("snap error: %s" % e)
            return 0, 0, b''

def log(msg):
    with open(LOG, 'a') as f:
        f.write("[L] %s\n" % msg)

def dismiss_all(q):
    """Aggressively dismiss startup dialogs."""
    log("Dismissing dialogs...")
    # Click center of screen to get focus
    q.hmp('mouse_move 512 384')
    time.sleep(0.1)
    q.hmp('mouse_button 1')
    time.sleep(0.2)
    q.hmp('mouse_button 0')
    time.sleep(0.5)
    
    # Try multiple dismiss methods
    for i in range(5):
        q.key('esc', 0.3)
    q.key('ret', 0.5)
    
    # Click potential OK/Close buttons at common positions
    # Bottom-center of dialog
    for x, y in [(512, 450), (512, 500), (550, 450), (400, 450), (700, 50)]:
        q.hmp('mouse_move %d %d' % (x, y))
        time.sleep(0.1)
        q.hmp('mouse_button 1')
        time.sleep(0.1)
        q.hmp('mouse_button 0')
        time.sleep(0.3)
    
    q.key('esc', 0.5)
    q.key('esc', 0.5)
    time.sleep(1)

def launch_via_run(q):
    """Open Run dialog and type the game path."""
    log("Opening Run dialog (Win+R)...")
    # Win+R is more reliable than Start menu navigation
    # In QEMU, Windows key is 'meta_l'
    q.hmp('sendkey meta_l-r 200')
    time.sleep(2.0)
    
    q.snap("after_winR")
    
    # Clear any existing text
    q.key('ctrl-a', 0.2)
    q.key('delete', 0.3)
    
    # Type the 8.3 path (verified from disk image):
    # C:\PROGRA~1\LEGOME~1\CONSTR~1\LEGOLO~1\EXE\LOCO.EXE
    path_keys = [
        'shift-c', 'shift-semicolon', 'backslash',  # C:\
        'shift-p','shift-r','shift-o','shift-g','shift-r','shift-a',  # PROGRA
        'shift-grave_accent', '1', 'backslash',  # ~1\
        'shift-l','shift-e','shift-g','shift-o','shift-m','shift-e',  # LEGOME
        'shift-grave_accent', '1', 'backslash',  # ~1\
        'shift-c','shift-o','shift-n','shift-s','shift-t','shift-r',  # CONSTR
        'shift-grave_accent', '1', 'backslash',  # ~1\
        'shift-l','shift-e','shift-g','shift-o','shift-l','shift-o',  # LEGOLO
        'shift-grave_accent', '1', 'backslash',  # ~1\
        'shift-e','shift-x','shift-e', 'backslash',  # EXE\
        'shift-l','shift-o','shift-c','shift-o',  # LOCO
        'dot',  # .
        'shift-e','shift-x','shift-e',  # EXE
    ]
    
    log("Typing path...")
    q.keys(path_keys, 0.05)
    time.sleep(0.5)
    
    q.snap("path_typed")
    
    log("Pressing Enter to launch...")
    q.key('ret', 1.0)

def launch_via_startmenu(q):
    """Try launching via Start > Programs > LEGO."""
    log("Trying Start menu approach...")
    q.key('ctrl-esc', 1.5)  # Open start menu
    
    # Programs is usually the first item
    q.key('p', 1.0)  # P should highlight "Programs"
    
    q.snap("start_programs")
    
    # In submenu, look for LEGO
    q.key('l', 0.5)  # L for LEGO
    q.key('ret', 0.5)  # Open LEGO submenu
    q.key('l', 0.5)  # L for LEGO LOCO
    q.key('ret', 2.0)  # Launch
    
def main():
    iid = int(os.environ.get('INSTANCE_ID', '0'))
    sock = '/tmp/qmp-%d.sock' % iid
    open(LOG, 'w').close()
    log("=== Game Launcher START (id=%d) ===" % iid)
    
    q = QMP(sock)
    log("QMP connected")
    
    # Step 1: See current state
    q.snap("initial_state")
    
    # Step 2: Dismiss any dialogs
    dismiss_all(q)
    q.snap("after_dismiss")
    
    # Step 3: Try Run dialog method first
    launch_via_run(q)
    
    # Step 4: Monitor for game launch
    log("Monitoring game launch...")
    for wait in [3, 5, 10, 15, 20]:
        time.sleep(wait - (3 if wait > 3 else 0))
        q.snap("game_t%ds" % wait)
    
    # Step 5: If screen still looks like desktop (high white/gray), try alt approach
    # Check last screenshot
    q.snap("final_check")
    
    # Step 6: Try dismissing intro videos if game loaded (Esc key)
    log("Attempting to dismiss intro/videos...")
    for _ in range(5):
        q.key('esc', 1.0)
    
    q.snap("after_video_dismiss")
    
    # Step 7: If game didn't load, try double-clicking desktop shortcut
    # LEGO LOCO might have a desktop shortcut
    log("Trying desktop shortcut click...")
    # Desktop icons are usually at top-left
    # A typical desktop icon position: (40, 40), (40, 100), etc.
    # But first let me check if game loaded by looking at previous results
    
    q.s.close()
    log("=== DONE ===")

if __name__ == '__main__':
    main()
