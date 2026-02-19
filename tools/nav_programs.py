#!/usr/bin/env python3
"""Navigate Start -> Programs to find and launch LEGO LOCO."""
import json, socket, time, sys, os

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
                    try:
                        return json.loads(line)
                    except:
                        pass
                continue
            try:
                c = self.s.recv(4096)
                if not c:
                    return {}
                self.buf += c
            except socket.timeout:
                return {}

    def cmd(self, ex, args=None):
        m = {'execute': ex}
        if args:
            m['arguments'] = args
        self.s.sendall(json.dumps(m).encode() + b'\n')
        for _ in range(20):
            r = self._read()
            if 'return' in r or 'error' in r:
                return r
        return {}

    def hmp(self, c):
        return self.cmd('human-monitor-command', {'command-line': c})

    def key(self, name, delay=0.3):
        self.hmp('sendkey %s 100' % name)
        time.sleep(delay)

    def snap(self, label=""):
        self.cmd('screendump', {'filename': '/tmp/ss.ppm'})
        time.sleep(0.4)
        with open('/tmp/ss.ppm', 'rb') as f:
            f.readline()
            line = f.readline()
            while line.startswith(b'#'):
                line = f.readline()
            w, h = map(int, line.split())
            f.readline()
            data = f.read()
        cats = {'W': 0, 'B': 0, 'G': 0, 'O': 0}
        for y in range(0, h, 15):
            for x in range(0, w, 15):
                i = (y * w + x) * 3
                r, g, b = data[i], data[i+1], data[i+2]
                if r > 220 and g > 220 and b > 220:
                    cats['W'] += 1
                elif r < 30 and g < 30 and b < 30:
                    cats['B'] += 1
                elif 180 < r < 230 and abs(r-g) < 10 and abs(r-b) < 10:
                    cats['G'] += 1
                else:
                    cats['O'] += 1
        t = max(sum(cats.values()), 1)
        ci = (384 * w + 512) * 3
        cr, cg, cb = data[ci], data[ci+1], data[ci+2]
        msg = "%s: W=%d%% B=%d%% G=%d%% O=%d%% ctr=(%d,%d,%d)" % (
            label, cats['W']*100//t, cats['B']*100//t,
            cats['G']*100//t, cats['O']*100//t, cr, cg, cb)
        log(msg)
        return w, h, data

    def px(self, data, w, x, y):
        i = (y * w + x) * 3
        if i + 2 < len(data):
            return data[i], data[i+1], data[i+2]
        return 0, 0, 0


def log(msg):
    line = "[NAV] %s\n" % msg
    sys.stdout.write(line)
    sys.stdout.flush()
    with open('/tmp/nav_log.txt', 'a') as f:
        f.write(line)


def main():
    iid = int(os.environ.get('INSTANCE_ID', '0'))
    sock = '/tmp/qmp-%d.sock' % iid
    open('/tmp/nav_log.txt', 'w').close()

    log("Connecting instance=%d" % iid)
    q = QMP(sock)
    log("Connected")

    # Dismiss startup dialogs
    log("=== Dismissing dialogs ===")
    for _ in range(5):
        q.key('ret', 0.3)
        q.key('esc', 0.3)
    time.sleep(1)
    q.key('esc', 0.5)
    q.key('esc', 0.5)
    q.snap("dismissed")

    # Open Start menu
    log("=== Opening Start menu ===")
    q.key('ctrl-esc', 2.0)
    w, h, d = q.snap("start_menu")

    # Check for blue strip (Start menu indicator)
    blue = 0
    for y in range(400, 741, 5):
        r, g, b = q.px(d, w, 10, y)
        if b > 100 and r < 30 and g < 30:
            blue += 1
    log("Blue strip: %d (need >5)" % blue)

    # Navigate to Programs (top of menu)
    # From bottom: ShutDown, Run, Help, Find, Settings, Documents, Favorites, Programs
    # Press Up many times to get to top (Programs)
    log("=== Navigating to Programs ===")
    for i in range(10):
        q.key('up', 0.15)
    time.sleep(0.5)
    q.snap("at_top")

    # Press Right to open Programs submenu
    log("Opening Programs submenu...")
    q.key('right', 1.0)
    q.snap("programs_open")

    # Now look for LEGO entry in the Programs submenu
    # Navigate through items - press Down to cycle through entries
    # Take screenshots at each position to detect the LEGO entry
    log("=== Scanning Programs menu items ===")
    for item_num in range(20):
        w, h, d = q.snap("prog_item_%d" % item_num)
        # Check if we see highlighted/selected text with LEGO colors
        # In Win98, selected item has blue background
        # Just log the center-left area to identify items
        r60, g60, b60 = q.px(d, w, 60, 384)
        r200, g200, b200 = q.px(d, w, 200, 384)
        log("  item %d: px60=(%d,%d,%d) px200=(%d,%d,%d)" % (
            item_num, r60, g60, b60, r200, g200, b200))
        q.key('down', 0.3)
    
    # After scanning, go back and try to find LEGO by pressing 'l'
    log("=== Trying letter jump 'l' for LEGO ===")
    q.key('esc', 0.5)
    q.key('esc', 0.5)
    time.sleep(0.5)
    
    # Reopen Start -> Programs
    q.key('ctrl-esc', 1.5)
    for i in range(10):
        q.key('up', 0.15)
    q.key('right', 1.0)
    
    # Press 'l' to jump to L-entries
    q.key('l', 0.5)
    q.snap("after_l_key")
    
    # Open submenu if it's a folder
    q.key('right', 1.0)
    q.snap("after_l_right")
    
    # Try pressing 'l' again for nested LEGO folder
    q.key('l', 0.5)
    q.snap("after_l_l")
    
    # Open that submenu
    q.key('right', 1.0)
    q.snap("after_l_l_right")
    
    # Press Enter on first item
    q.key('ret', 3.0)
    q.snap("after_enter")
    
    # Wait to see if game launched
    time.sleep(5)
    q.snap("after_5s")
    
    time.sleep(5)
    q.snap("after_10s")
    
    time.sleep(10)
    q.snap("after_20s")

    q.s.close()
    log("DONE")


if __name__ == '__main__':
    main()
