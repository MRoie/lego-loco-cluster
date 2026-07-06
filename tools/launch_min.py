#!/usr/bin/env python3
"""Minimal game launcher: Open Run dialog, type path, launch."""
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
    def typechar(self, ch, delay=0.06):
        KEYS = {
            ' ': 'spc', '.': 'dot', ',': 'comma', '-': 'minus',
            '\\': 'backslash', '/': 'slash',
            ':': 'shift-semicolon', ';': 'semicolon',
            '(': 'shift-9', ')': 'shift-0',
            '"': 'shift-apostrophe', "'": 'apostrophe',
            '~': 'shift-grave_accent', '!': 'shift-1',
        }
        if ch.isupper():
            k = 'shift-%s' % ch.lower()
        elif ch.isalpha() or ch.isdigit():
            k = ch
        else:
            k = KEYS.get(ch)
            if not k:
                log("SKIP char '%s'" % ch)
                return
        self.hmp('sendkey %s 50' % k)
        time.sleep(delay)
    def screenshot_analyze(self, label=""):
        self.cmd('screendump', {'filename': '/tmp/ss.ppm'})
        time.sleep(0.3)
        with open('/tmp/ss.ppm', 'rb') as f:
            f.readline()
            line = f.readline()
            while line.startswith(b'#'): line = f.readline()
            w, h = map(int, line.split())
            f.readline()
            d = f.read()
        # quick stats
        categories = {'W':0,'B':0,'G':0,'O':0}
        for y in range(0, h, 15):
            for x in range(0, w, 15):
                i = (y*w+x)*3
                r,g,b = d[i],d[i+1],d[i+2]
                if r>220 and g>220 and b>220: categories['W']+=1
                elif r<30 and g<30 and b<30: categories['B']+=1
                elif 180<r<230 and abs(r-g)<10 and abs(r-b)<10: categories['G']+=1
                else: categories['O']+=1
        t = max(sum(categories.values()),1)
        # center pixel
        ci = (384*w+512)*3
        cr,cg,cb = d[ci],d[ci+1],d[ci+2]
        log("%s: W=%d%% B=%d%% G=%d%% O=%d%% center=(%d,%d,%d)" % (
            label, categories['W']*100//t, categories['B']*100//t,
            categories['G']*100//t, categories['O']*100//t, cr, cg, cb))
        return w, h, d

def log(msg):
    with open('/tmp/launch_log.txt', 'a') as f:
        f.write("[L] %s\n" % msg)

def main():
    iid = int(os.environ.get('INSTANCE_ID', '0'))
    sock = '/tmp/qmp-%d.sock' % iid
    
    # Clear log
    open('/tmp/launch_log.txt', 'w').close()
    
    log("START instance=%d" % iid)
    q = QMP(sock)
    log("QMP connected")
    
    # Dismiss any open windows/dialogs
    q.key('esc', 0.5)
    q.key('esc', 0.5)
    q.key('esc', 0.5)
    time.sleep(0.5)
    q.screenshot_analyze("after_dismiss")
    
    # Open Start menu
    q.key('ctrl-esc', 2.0)
    q.screenshot_analyze("start_menu")
    
    # Navigate: Up=Shut Down, Up=Run, Enter
    q.key('up', 0.4)
    q.key('up', 0.4)
    q.key('ret', 2.0)
    q.screenshot_analyze("run_dialog")
    
    # Clear the text field
    q.key('ctrl-a', 0.2)
    q.key('delete', 0.3)
    time.sleep(0.2)
    
    # Type the game path with quotes (handles spaces)
    # "C:\Program Files\LEGO Media\Constructive\LEGO LOCO\Exe\Loco.exe"
    path = '"C:\\Program Files\\LEGO Media\\Constructive\\LEGO LOCO\\Exe\\Loco.exe"'
    log("Typing path: %s" % path)
    for ch in path:
        q.typechar(ch, 0.06)
    
    time.sleep(0.3)
    q.screenshot_analyze("after_type")
    
    # Press OK (Enter)
    log("Pressing Enter to launch...")
    q.key('ret', 1.0)
    
    # Wait for game to start (might take a while)
    for wait_sec in [3, 5, 5, 10, 10]:
        time.sleep(wait_sec)
        q.screenshot_analyze("wait_%ds" % wait_sec)
    
    q.s.close()
    log("DONE")

if __name__ == '__main__':
    main()
