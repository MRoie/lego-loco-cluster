#!/usr/bin/env python3
"""Test Run dialog: open cmd, then list the game folder to find the right path."""
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
    def snap(self, label=""):
        self.cmd('screendump', {'filename': '/tmp/ss.ppm'})
        time.sleep(0.4)
        with open('/tmp/ss.ppm', 'rb') as f:
            f.readline()
            line = f.readline()
            while line.startswith(b'#'): line = f.readline()
            w, h = map(int, line.split())
            f.readline()
            data = f.read()
        cats = {'W': 0, 'B': 0, 'G': 0, 'O': 0}
        for y in range(0, h, 15):
            for x in range(0, w, 15):
                i = (y * w + x) * 3
                r, g, b = data[i], data[i+1], data[i+2]
                if r > 220 and g > 220 and b > 220: cats['W'] += 1
                elif r < 30 and g < 30 and b < 30: cats['B'] += 1
                elif 180 < r < 230 and abs(r-g) < 10 and abs(r-b) < 10: cats['G'] += 1
                else: cats['O'] += 1
        t = max(sum(cats.values()), 1)
        msg = "%s: W=%d%% B=%d%% G=%d%% O=%d%%" % (
            label, cats['W']*100//t, cats['B']*100//t,
            cats['G']*100//t, cats['O']*100//t)
        log(msg)
        return w, h, data
    def px(self, data, w, x, y):
        i = (y * w + x) * 3
        if i + 2 < len(data): return data[i], data[i+1], data[i+2]
        return 0, 0, 0

def log(msg):
    line = "[T] %s\n" % msg
    sys.stdout.write(line)
    sys.stdout.flush()
    with open('/tmp/test_log.txt', 'a') as f:
        f.write(line)

def main():
    iid = int(os.environ.get('INSTANCE_ID', '0'))
    sock = '/tmp/qmp-%d.sock' % iid
    open('/tmp/test_log.txt', 'w').close()

    log("START id=%d" % iid)
    q = QMP(sock)
    log("Connected")

    # Dismiss dialogs
    q.key('esc', 0.5)
    q.key('esc', 0.5)
    q.key('esc', 0.5)
    time.sleep(0.5)

    # Open Run dialog: Start -> Up -> Up -> Enter
    log("Opening Run dialog...")
    q.key('ctrl-esc', 1.5)
    q.key('up', 0.3)
    q.key('up', 0.3)
    q.key('ret', 2.0)
    q.snap("run_dialog")

    # Test 1: Just type "cmd" and press Enter to open a command prompt
    log("Test 1: Opening cmd...")
    q.hmp('sendkey c 50')
    time.sleep(0.06)
    q.hmp('sendkey m 50')
    time.sleep(0.06)
    q.hmp('sendkey d 50')
    time.sleep(0.3)
    q.key('ret', 3.0)
    q.snap("cmd_opened")

    # Now in cmd, type 'dir' to see if the command prompt works
    log("Typing 'dir' in cmd...")
    q.hmp('sendkey d 50')
    time.sleep(0.06)
    q.hmp('sendkey i 50')
    time.sleep(0.06)
    q.hmp('sendkey r 50')
    time.sleep(0.06)
    q.hmp('sendkey spc 50')
    time.sleep(0.06)
    # Type: C:\PROGRA~1
    q.hmp('sendkey shift-c 50')
    time.sleep(0.06)
    q.hmp('sendkey shift-semicolon 50')  # :
    time.sleep(0.06)
    q.hmp('sendkey backslash 50')        # backslash
    time.sleep(0.06)
    # Type PROGRA~1
    q.hmp('sendkey shift-p 50')
    time.sleep(0.06)
    q.hmp('sendkey shift-r 50')
    time.sleep(0.06)
    q.hmp('sendkey shift-o 50')
    time.sleep(0.06)
    q.hmp('sendkey shift-g 50')
    time.sleep(0.06)
    q.hmp('sendkey shift-r 50')
    time.sleep(0.06)
    q.hmp('sendkey shift-a 50')
    time.sleep(0.06)
    q.hmp('sendkey shift-grave_accent 50')  # ~
    time.sleep(0.06)
    q.hmp('sendkey 1 50')
    time.sleep(0.06)
    q.key('ret', 2.0)
    q.snap("dir_result")

    # Try: dir C:\PROGRA~1 /x
    log("Typing 'dir /x' to see 8.3 names...")
    q.hmp('sendkey d 50')
    time.sleep(0.06)
    q.hmp('sendkey i 50')
    time.sleep(0.06)
    q.hmp('sendkey r 50')
    time.sleep(0.06)
    q.hmp('sendkey spc 50')
    time.sleep(0.06)
    q.hmp('sendkey slash 50')  # /
    time.sleep(0.06)
    q.hmp('sendkey x 50')
    time.sleep(0.06)
    q.key('ret', 2.0)

    # Check if we can see the dir output in the window
    # The cmd window should show directory listing
    w, h, d = q.snap("dir_x_result")

    # Sample pixels where CMD window would be
    # CMD window typically appears at top-left in windowed mode
    # Let's check a broader area
    log("Sampling screen regions:")
    for y_pos in range(50, 700, 50):
        black_count = 0
        for x_pos in range(10, 800, 10):
            r, g, b = q.px(d, w, x_pos, y_pos)
            if r < 30 and g < 30 and b < 30:
                black_count += 1
        if black_count > 5:
            log("  y=%d: %d black pixels (text row?)" % (y_pos, black_count))

    # Now try to exit cmd and use Run dialog to launch the game directly
    log("Exiting cmd...")
    q.hmp('sendkey e 50')
    time.sleep(0.06)
    q.hmp('sendkey x 50')
    time.sleep(0.06)
    q.hmp('sendkey i 50')
    time.sleep(0.06)
    q.hmp('sendkey t 50')
    time.sleep(0.3)
    q.key('ret', 1.0)

    # Now open Run dialog again for the game
    log("Opening Run dialog for game launch...")
    q.key('ctrl-esc', 1.5)
    q.key('up', 0.3)
    q.key('up', 0.3)
    q.key('ret', 2.0)
    q.snap("run_for_game")

    # Clear field and type the game path
    q.key('ctrl-a', 0.2)
    q.key('delete', 0.3)

    # Type the full path character by character using sendkey
    # Path: "C:\Program Files\LEGO Media\Constructive\LEGO LOCO\Exe\Loco.exe"
    # Note: In Run dialog, you don't need quotes if the path is valid
    # Let's try without quotes first - Win98 Run dialog often handles spaces
    log("Typing game path...")

    # C:\Program Files\LEGO Media\Constructive\LEGO LOCO\Exe\Loco.exe
    path_keys = [
        ('shift-c', 'C'),
        ('shift-semicolon', ':'),
        ('backslash', '\\'),
        ('shift-p', 'P'), ('r', 'r'), ('o', 'o'), ('g', 'g'), ('r', 'r'),
        ('a', 'a'), ('m', 'm'), ('spc', ' '),
        ('shift-f', 'F'), ('i', 'i'), ('l', 'l'), ('e', 'e'), ('s', 's'),
        ('backslash', '\\'),
        ('shift-l', 'L'), ('shift-e', 'E'), ('shift-g', 'G'), ('shift-o', 'O'),
        ('spc', ' '),
        ('shift-m', 'M'), ('e', 'e'), ('d', 'd'), ('i', 'i'), ('a', 'a'),
        ('backslash', '\\'),
        ('shift-c', 'C'), ('o', 'o'), ('n', 'n'), ('s', 's'), ('t', 't'),
        ('r', 'r'), ('u', 'u'), ('c', 'c'), ('t', 't'), ('i', 'i'),
        ('v', 'v'), ('e', 'e'),
        ('backslash', '\\'),
        ('shift-l', 'L'), ('shift-e', 'E'), ('shift-g', 'G'), ('shift-o', 'O'),
        ('spc', ' '),
        ('shift-l', 'L'), ('shift-o', 'O'), ('shift-c', 'C'), ('shift-o', 'O'),
        ('backslash', '\\'),
        ('shift-e', 'E'), ('x', 'x'), ('e', 'e'),
        ('backslash', '\\'),
        ('shift-l', 'L'), ('o', 'o'), ('c', 'c'), ('o', 'o'), ('dot', '.'),
        ('e', 'e'), ('x', 'x'), ('e', 'e'),
    ]

    typed = ""
    for key_name, char_repr in path_keys:
        q.hmp('sendkey %s 50' % key_name)
        typed += char_repr
        time.sleep(0.05)

    log("Typed: %s" % typed)
    time.sleep(0.5)
    q.snap("path_typed")

    # Press Enter to launch
    log("Pressing Enter to launch game...")
    q.key('ret', 3.0)
    q.snap("after_launch_enter")

    # Wait and check
    for secs in [3, 5, 10, 10]:
        time.sleep(secs)
        w, h, d = q.snap("wait_%ds" % secs)
        # Check if game started (lots of non-white/non-gray)
        non_desk = 0
        t2 = 0
        for y in range(0, h, 15):
            for x in range(0, w, 15):
                i = (y*w+x)*3
                r, g, b = d[i], d[i+1], d[i+2]
                t2 += 1
                if not (r > 200 and g > 200 and b > 200) and \
                   not (180 < r < 230 and abs(r-g) < 10 and abs(r-b) < 10):
                    non_desk += 1
        pct = non_desk * 100 // max(t2, 1)
        log("Non-desktop: %d%% (game if >30%%)" % pct)
        if pct > 30:
            log("GAME DETECTED!")
            break

    q.s.close()
    log("DONE")

if __name__ == '__main__':
    main()
