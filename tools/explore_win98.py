#!/usr/bin/env python3
"""Step-by-step Win98 explorer to find and launch Lego Loco."""
import json, socket, time, sys

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

    def hmp(self, cmd_str):
        return self.cmd('human-monitor-command', {'command-line': cmd_str})

    def key(self, name, delay=0.3):
        self.hmp('sendkey %s 100' % name)
        time.sleep(delay)

    def typetext(self, text, delay=0.06):
        """Type text character by character."""
        KEYMAP = {
            'a': 'a', 'b': 'b', 'c': 'c', 'd': 'd', 'e': 'e',
            'f': 'f', 'g': 'g', 'h': 'h', 'i': 'i', 'j': 'j',
            'k': 'k', 'l': 'l', 'm': 'm', 'n': 'n', 'o': 'o',
            'p': 'p', 'q': 'q', 'r': 'r', 's': 's', 't': 't',
            'u': 'u', 'v': 'v', 'w': 'w', 'x': 'x', 'y': 'y',
            'z': 'z',
            '0': '0', '1': '1', '2': '2', '3': '3', '4': '4',
            '5': '5', '6': '6', '7': '7', '8': '8', '9': '9',
            ' ': 'spc',
            '.': 'dot',
            ',': 'comma',
            '-': 'minus',
            '=': 'equal',
            '/': 'slash',
            ';': 'semicolon',
            ':': 'shift-semicolon',
            '\\': 'backslash',
            '~': 'shift-grave_accent',
            '`': 'grave_accent',
            '!': 'shift-1',
            '@': 'shift-2',
            '#': 'shift-3',
            '$': 'shift-4',
            '%': 'shift-5',
            '^': 'shift-6',
            '&': 'shift-7',
            '*': 'shift-8',
            '(': 'shift-9',
            ')': 'shift-0',
            '_': 'shift-minus',
            '+': 'shift-equal',
            '"': 'shift-apostrophe',
            "'": 'apostrophe',
            '[': 'bracket_left',
            ']': 'bracket_right',
        }
        for ch in text:
            if ch.isupper():
                k = 'shift-%s' % ch.lower()
            else:
                k = KEYMAP.get(ch)
                if k is None:
                    log("WARNING: unmapped char '%s' (ord %d)" % (ch, ord(ch)))
                    continue
            self.hmp('sendkey %s 50' % k)
            time.sleep(delay)

    def screenshot(self, path='/tmp/ss.ppm'):
        self.cmd('screendump', {'filename': path})
        time.sleep(0.4)

    def get_pixel(self, data, w, x, y):
        i = (y * w + x) * 3
        if i + 2 < len(data):
            return data[i], data[i+1], data[i+2]
        return 0, 0, 0

    def read_screen(self, path='/tmp/ss.ppm'):
        with open(path, 'rb') as f:
            f.readline()  # P6
            line = f.readline()
            while line.startswith(b'#'):
                line = f.readline()
            w, h = map(int, line.split())
            f.readline()  # maxval
            data = f.read()
        return w, h, data


def log(msg):
    print("[STEP] %s" % msg, flush=True)


def analyze_screen(q, label=""):
    """Take screenshot and report what we see."""
    q.screenshot('/tmp/ss_step.ppm')
    w, h, d = q.read_screen('/tmp/ss_step.ppm')
    
    # Count color categories
    black = white = gray = teal = blue = other = 0
    total = 0
    for y in range(0, h, 10):
        for x in range(0, w, 10):
            r, g, b = q.get_pixel(d, w, x, y)
            total += 1
            if r < 30 and g < 30 and b < 30:
                black += 1
            elif r > 220 and g > 220 and b > 220:
                white += 1
            elif 180 < r < 230 and abs(r-g) < 10 and abs(r-b) < 10:
                gray += 1
            elif g > 100 and b > 100 and r < 30:
                teal += 1
            elif b > 100 and r < 30 and g < 30:
                blue += 1
            else:
                other += 1
    
    log("%s: W=%d%% Blk=%d%% Gry=%d%% Tl=%d%% Blu=%d%% Oth=%d%%" % (
        label, white*100//total, black*100//total, gray*100//total,
        teal*100//total, blue*100//total, other*100//total))
    
    # Sample key spots
    for name, x, y in [('center', 512, 384), ('bar', 512, 750), ('top', 512, 30)]:
        r, g, b = q.get_pixel(d, w, x, y)
        log("  %s(%d,%d): RGB(%d,%d,%d)" % (name, x, y, r, g, b))
    
    return w, h, d


def main():
    sock = '/tmp/qmp-0.sock'
    log("Connecting to %s" % sock)
    q = QMP(sock)
    log("Connected")

    # Step 0: Dismiss everything
    log("=== STEP 0: Dismiss dialogs ===")
    q.key('esc', 0.5)
    q.key('esc', 0.5)
    q.key('esc', 0.5)
    time.sleep(1)
    analyze_screen(q, "After dismiss")

    # Step 1: Open Start menu
    log("=== STEP 1: Open Start menu ===")
    q.key('ctrl-esc', 2.0)
    w, h, d = analyze_screen(q, "After Ctrl+Esc")
    
    # Verify start menu by checking for blue strip at x=5-15, y=400-740
    blue_pixels = 0
    for y in range(400, 741, 5):
        r, g, b = q.get_pixel(d, w, 10, y)
        if b > 100 and r < 30 and g < 30:
            blue_pixels += 1
    log("  Blue strip check: %d blue pixels (need >5)" % blue_pixels)
    
    if blue_pixels < 3:
        log("Start menu not detected! Trying again...")
        q.key('esc', 1.0)
        q.key('ctrl-esc', 2.0)
        analyze_screen(q, "Retry Start")

    # Step 2: Navigate to Run (Up, Up from bottom = Shut Down, Run)
    log("=== STEP 2: Navigate to Run ===")
    q.key('up', 0.5)
    q.key('up', 0.5)
    analyze_screen(q, "After Up x2")
    
    q.key('ret', 2.5)
    w, h, d = analyze_screen(q, "After Enter (Run dialog?)")

    # Check for Run dialog = gray box in center
    gray_center = 0
    for y in range(300, 500, 10):
        for x in range(250, 750, 10):
            r, g, b = q.get_pixel(d, w, x, y)
            if 180 < r < 230 and abs(r-g) < 10 and abs(r-b) < 10:
                gray_center += 1
    log("  Gray center (dialog): %d (need >20)" % gray_center)

    if gray_center < 10:
        log("Run dialog not found! Trying alternate navigation...")
        # Maybe the Start menu has different items
        q.key('esc', 0.5)
        q.key('esc', 0.5)
        time.sleep(0.5)
        # Try just typing the path after Start menu
        q.key('ctrl-esc', 1.5)
        # In Win98, you can sometimes just type while start menu is open
        # Type 'r' to get to Run if it's highlighted
        q.key('r', 2.0)
        analyze_screen(q, "After pressing R in Start")
    
    # Step 3: Type command to check filesystem
    log("=== STEP 3: Type command ===")
    # Clear any existing text
    q.key('ctrl-a', 0.2)
    q.key('delete', 0.3)
    
    # First try: just type "command" to get a DOS prompt
    q.typetext("command", 0.08)
    time.sleep(0.3)
    q.key('ret', 3.0)
    analyze_screen(q, "After 'command' Enter")

    # Step 4: In command prompt, list the directory
    log("=== STEP 4: List directories ===")
    
    # Type: dir C:\PROGRA~1 /x
    q.typetext("dir c:", 0.06)
    q.key('backslash', 0.06)
    q.typetext("progra~1", 0.06)
    q.key('spc', 0.06)
    q.key('slash', 0.06)
    q.typetext("x", 0.06)
    q.key('ret', 2.0)
    analyze_screen(q, "dir progra~1")

    # Scroll up and check for LEGO entries
    # Also try: dir /x to see 8.3 names
    q.typetext("dir c:", 0.06)
    q.key('backslash', 0.06)
    q.typetext("progra~1", 0.06)
    q.key('backslash', 0.06)
    q.typetext("lego*", 0.06)
    q.key('spc', 0.06)
    q.key('slash', 0.06)
    q.typetext("x", 0.06)
    q.key('ret', 2.0)
    analyze_screen(q, "dir lego*")

    # Also try the full path with quotes
    log("=== STEP 5: Try direct launch with quotes ===")
    q.typetext('exit', 0.06)
    q.key('ret', 1.0)
    
    # Back to desktop, open Run again
    q.key('ctrl-esc', 1.5)
    q.key('up', 0.4)
    q.key('up', 0.4) 
    q.key('ret', 2.0)
    
    # Type the path with quotes
    q.key('ctrl-a', 0.2)
    q.key('delete', 0.3)
    
    # Type: "C:\Program Files\LEGO Media\Constructive\LEGO LOCO\Exe\Loco.exe"
    q.key('shift-apostrophe', 0.06)  # "
    q.typetext("C", 0.06)
    q.key('shift-semicolon', 0.06)  # :
    q.key('backslash', 0.06)        # \
    q.typetext("Program Files", 0.06)
    q.key('backslash', 0.06)
    q.typetext("LEGO Media", 0.06)
    q.key('backslash', 0.06)
    q.typetext("Constructive", 0.06)
    q.key('backslash', 0.06)
    q.typetext("LEGO LOCO", 0.06)
    q.key('backslash', 0.06)
    q.typetext("Exe", 0.06)
    q.key('backslash', 0.06)
    q.typetext("Loco.exe", 0.06)
    q.key('shift-apostrophe', 0.06)  # "
    time.sleep(0.5)
    
    analyze_screen(q, "Typed full path")
    
    # Press Enter to launch
    q.key('ret', 5.0)
    analyze_screen(q, "After Enter (game?)")
    
    # Wait and check again
    time.sleep(5)
    analyze_screen(q, "After 5s wait")
    
    time.sleep(5)
    analyze_screen(q, "After 10s wait")

    q.s.close()
    log("Done!")


if __name__ == '__main__':
    main()
