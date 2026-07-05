#!/usr/bin/env python3
"""Test: verify Run dialog works by launching Calculator, then explore filesystem."""
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
    def snap(self, path='/tmp/ss.ppm'):
        self.cmd('screendump', {'filename': path})
        time.sleep(0.4)
        with open(path, 'rb') as f:
            f.readline()
            line = f.readline()
            while line.startswith(b'#'): line = f.readline()
            w, h = map(int, line.split())
            f.readline()
            data = f.read()
        return w, h, data
    def analyze(self, data, w, h, label=""):
        cats = {'W':0, 'B':0, 'G':0, 'O':0}
        for y in range(0, h, 12):
            for x in range(0, w, 12):
                i = (y*w+x)*3
                r,g,b = data[i], data[i+1], data[i+2]
                if r>220 and g>220 and b>220: cats['W'] += 1
                elif r<30 and g<30 and b<30: cats['B'] += 1
                elif 180<r<230 and abs(r-g)<10 and abs(r-b)<10: cats['G'] += 1
                else: cats['O'] += 1
        t = max(sum(cats.values()), 1)
        log("%s: W=%d%% B=%d%% G=%d%% O=%d%%" % (
            label, cats['W']*100//t, cats['B']*100//t,
            cats['G']*100//t, cats['O']*100//t))
    def px(self, data, w, x, y):
        i = (y*w+x)*3
        if i+2 < len(data): return data[i], data[i+1], data[i+2]
        return 0, 0, 0

def log(msg):
    line = "[R] %s\n" % msg
    with open('/tmp/run_test.txt', 'a') as f:
        f.write(line)

def open_run(q):
    """Open the Run dialog reliably."""
    q.key('ctrl-esc', 1.5)
    q.key('up', 0.3)
    q.key('up', 0.3)
    q.key('ret', 2.0)
    # Clear any existing text
    q.key('ctrl-a', 0.2)
    q.key('delete', 0.3)

def type_and_run(q, keys_list, label=""):
    """Type keystrokes into Run dialog field and press Enter."""
    for key_name in keys_list:
        q.hmp('sendkey %s 50' % key_name)
        time.sleep(0.05)
    time.sleep(0.3)
    log("Typed: %s" % label)
    q.key('ret', 3.0)

def main():
    iid = int(os.environ.get('INSTANCE_ID', '0'))
    sock = '/tmp/qmp-%d.sock' % iid
    open('/tmp/run_test.txt', 'w').close()
    log("START id=%d" % iid)
    
    q = QMP(sock)
    log("Connected")
    
    # Dismiss everything
    for _ in range(3):
        q.key('esc', 0.3)
    time.sleep(0.5)
    
    w, h, d = q.snap()
    q.analyze(d, w, h, "initial")

    # TEST 1: Launch Calculator (always exists)
    log("=== TEST 1: Launch calc ===")
    open_run(q)
    # Type: calc
    type_and_run(q, ['c','a','l','c'], "calc")
    
    w, h, d = q.snap()
    q.analyze(d, w, h, "after_calc")
    
    # Close calc
    q.key('alt-f4', 1.0)

    # TEST 2: Launch Explorer at C:\
    log("=== TEST 2: Explorer C:\\ ===")
    open_run(q)
    # Type: explorer /e,C:\
    # Keys: e x p l o r e r spc slash e comma shift-c shift-semicolon backslash
    type_and_run(q, [
        'e','x','p','l','o','r','e','r','spc',
        'slash','e','comma',
        'shift-c','shift-semicolon','backslash'
    ], "explorer /e,C:\\")
    
    time.sleep(2)
    w, h, d = q.snap()
    q.analyze(d, w, h, "explorer_c")
    
    # Maximize the explorer window
    q.key('alt-spc', 0.3)
    q.key('x', 1.0)
    w, h, d = q.snap()
    q.analyze(d, w, h, "explorer_max")
    
    # Close explorer
    q.key('alt-f4', 1.0)

    # TEST 3: Open command.com (the Win98 shell, not cmd)
    log("=== TEST 3: command.com ===")
    open_run(q)
    # Type: command.com /c dir "C:\PROGRA~1" & pause
    # This lists Program Files and pauses so we can see the output
    type_and_run(q, [
        'c','o','m','m','a','n','d','dot','c','o','m'
    ], "command.com")
    
    time.sleep(2)
    w, h, d = q.snap()
    q.analyze(d, w, h, "command_com")
    
    # Now type dir command to check for LEGO
    # Type: dir C:\PROGRA~1\LEGO*
    log("Typing dir command...")
    keys = [
        'd','i','r','spc',
        'shift-c','shift-semicolon','backslash',  # C:\
        'shift-p','shift-r','shift-o','shift-g','shift-r','shift-a',  # PROGRA
        'shift-grave_accent','1','backslash',  # ~1\ 
        'shift-l','shift-e','shift-g','shift-o',  # LEGO
        'shift-8'  # *
    ]
    for k in keys:
        q.hmp('sendkey %s 50' % k)
        time.sleep(0.05)
    q.key('ret', 2.0)
    
    w, h, d = q.snap()
    q.analyze(d, w, h, "dir_lego")
    
    # Sample where DOS text would be (white text on black bg, or black on white)
    # DOS window in Win98 defaults to windowed mode, 80x25 chars
    # Check multiple y positions for black regions (text area)
    log("Looking for DOS text areas:")
    for y_pos in [100, 150, 200, 250, 300, 350, 400, 450, 500, 550, 600]:
        black = 0
        white = 0
        for x_pos in range(0, w, 5):
            r, g, b = q.px(d, w, x_pos, y_pos)
            if r < 30 and g < 30 and b < 30: black += 1
            if r > 220 and g > 220 and b > 220: white += 1
        if black > 20 or (black > 5 and white > 20):
            log("  y=%d: B=%d W=%d (possible text row)" % (y_pos, black, white))
    
    # Also check if we can detect the DOS window by looking for the title bar
    # Win98 DOS window title bar is typically at the top of the window
    log("Looking for window title bars (blue):")
    for y_pos in range(0, h, 10):
        blue = 0
        for x_pos in range(0, w, 10):
            r, g, b = q.px(d, w, x_pos, y_pos)
            if b > 100 and r < 50 and g < 50: blue += 1
        if blue > 5:
            log("  y=%d: %d blue pixels (title bar?)" % (y_pos, blue))

    # Type: dir C:\PROGRA~1\LEGOME~1\CONSTR~1\LEGOLO~1\Exe\ 
    log("Checking full game path...")
    # Type dir + full path
    keys2 = [
        'd','i','r','spc',
        'shift-c','shift-semicolon','backslash',
        'shift-p','shift-r','shift-o','shift-g','shift-r','shift-a',
        'shift-grave_accent','1','backslash',
        'shift-l','shift-e','shift-g','shift-o','shift-m','shift-e',
        'shift-grave_accent','1','backslash',
        'shift-c','shift-o','shift-n','shift-s','shift-t','shift-r',
        'shift-grave_accent','1','backslash',
        'shift-l','shift-e','shift-g','shift-o','shift-l','shift-o',
        'shift-grave_accent','1','backslash',
        'shift-e','x','e','backslash',
    ]
    for k in keys2:
        q.hmp('sendkey %s 50' % k)
        time.sleep(0.05)
    q.key('ret', 2.0)
    
    w, h, d = q.snap()
    q.analyze(d, w, h, "dir_full_path")

    # Try one more thing: check if the game exists with IF EXIST
    log("Testing IF EXIST...")
    # Type: if exist C:\PROGRA~1\LEGOME~1\CONSTR~1\LEGOLO~1\Exe\Loco.exe echo GAME_FOUND
    keys3 = [
        'i','f','spc','e','x','i','s','t','spc',
        'shift-c','shift-semicolon','backslash',
        'shift-p','shift-r','shift-o','shift-g','shift-r','shift-a',
        'shift-grave_accent','1','backslash',
        'shift-l','shift-e','shift-g','shift-o','shift-m','shift-e',
        'shift-grave_accent','1','backslash',
        'shift-c','shift-o','shift-n','shift-s','shift-t','shift-r',
        'shift-grave_accent','1','backslash',
        'shift-l','shift-e','shift-g','shift-o','shift-l','shift-o',
        'shift-grave_accent','1','backslash',
        'shift-e','x','e','backslash',
        'shift-l','o','c','o','dot','e','x','e',
        'spc','e','c','h','o','spc',
        'shift-g','shift-a','shift-m','shift-e','shift-minus',
        'shift-f','shift-o','shift-u','shift-n','shift-d',
    ]
    for k in keys3:
        q.hmp('sendkey %s 50' % k)
        time.sleep(0.05)
    q.key('ret', 2.0)
    
    w, h, d = q.snap()
    q.analyze(d, w, h, "if_exist")

    # Try alt approach: check without ~1 in case names are different  
    log("Testing alternate paths...")
    # dir C:\PROGRA~1\LEGO*
    alt_keys = [
        'd','i','r','spc','slash','x','spc',
        'shift-c','shift-semicolon','backslash',
        'shift-p','shift-r','shift-o','shift-g','shift-r','shift-a',
        'shift-grave_accent','1',
    ]
    for k in alt_keys:
        q.hmp('sendkey %s 50' % k)
        time.sleep(0.05)
    q.key('ret', 2.0)
    
    w, h, d = q.snap()
    q.analyze(d, w, h, "dir_progra_x")

    # Close command.com  
    keys_exit = ['e','x','i','t']
    for k in keys_exit:
        q.hmp('sendkey %s 50' % k)
        time.sleep(0.05)
    q.key('ret', 1.0)

    # TEST 4: Try to launch game via Run dialog directly
    log("=== TEST 4: Direct game launch ===")
    open_run(q)
    
    # Type the full path with quotes
    # "C:\Program Files\LEGO Media\Constructive\LEGO LOCO\Exe\Loco.exe"
    game_keys = [
        'shift-apostrophe',  # "
        'shift-c','shift-semicolon','backslash',  # C:\
        'shift-p','r','o','g','r','a','m','spc',  # Program 
        'shift-f','i','l','e','s',  # Files
        'backslash',  # \
        'shift-l','shift-e','shift-g','shift-o','spc',  # LEGO 
        'shift-m','e','d','i','a',  # Media
        'backslash',  # \
        'shift-c','o','n','s','t','r','u','c','t','i','v','e',  # Constructive
        'backslash',  # \
        'shift-l','shift-e','shift-g','shift-o','spc',  # LEGO 
        'shift-l','shift-o','shift-c','shift-o',  # LOCO
        'backslash',  # \
        'shift-e','x','e',  # Exe
        'backslash',  # \
        'shift-l','o','c','o','dot','e','x','e',  # Loco.exe
        'shift-apostrophe',  # closing "
    ]
    for k in game_keys:
        q.hmp('sendkey %s 50' % k)
        time.sleep(0.05)
    time.sleep(0.5)
    
    w, h, d = q.snap()
    q.analyze(d, w, h, "game_path_typed")
    
    q.key('ret', 5.0)
    w, h, d = q.snap()
    q.analyze(d, w, h, "game_launch_5s")
    
    time.sleep(10)
    w, h, d = q.snap()
    q.analyze(d, w, h, "game_launch_15s")

    q.s.close()
    log("DONE")

if __name__ == '__main__':
    main()
