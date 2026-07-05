#!/usr/bin/env python3
"""Launch Lego Loco game via QMP automation on Win98 QEMU guest."""
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

    def hmp(self, cmd):
        return self.cmd('human-monitor-command', {'command-line': cmd})

    def key(self, name, delay=0.3):
        self.hmp('sendkey {} 100'.format(name))
        time.sleep(delay)

    def keys(self, names, delay=0.15):
        """Send multiple keys in sequence."""
        for n in names:
            self.key(n, delay)

    def typestr(self, text, delay=0.08):
        """Type a string char by char via HMP sendkey."""
        keymap = {
            ' ': 'spc', '.': 'dot', ',': 'comma',
            '\\': 'backslash', '/': 'slash',
            ':': 'shift-semicolon', ';': 'semicolon',
            '(': 'shift-9', ')': 'shift-0',
            '-': 'minus', '_': 'shift-minus',
            '=': 'equal', '+': 'shift-equal',
            '[': 'bracket_left', ']': 'bracket_right',
            '{': 'shift-bracket_left', '}': 'shift-bracket_right',
            '~': 'shift-grave_accent', '`': 'grave_accent',
            '!': 'shift-1', '@': 'shift-2', '#': 'shift-3',
            '$': 'shift-4', '%': 'shift-5', '^': 'shift-6',
            '&': 'shift-7', '*': 'shift-8',
            '"': 'shift-apostrophe', "'": 'apostrophe',
        }
        for ch in text:
            if ch.isupper():
                k = 'shift-{}'.format(ch.lower())
            elif ch.isalpha() or ch.isdigit():
                k = ch
            else:
                k = keymap.get(ch, ch)
            self.hmp('sendkey {} 50'.format(k))
            time.sleep(delay)

    def screenshot(self, path='/tmp/ss.ppm'):
        self.cmd('screendump', {'filename': path})
        time.sleep(0.3)
        return path

    def analyze_screen(self, path='/tmp/ss.ppm'):
        """Return (width, height, pixel_data)."""
        with open(path, 'rb') as f:
            f.readline()  # P6
            line = f.readline()
            while line.startswith(b'#'):
                line = f.readline()
            w, h = map(int, line.split())
            f.readline()  # maxval
            data = f.read()
        return w, h, data

    def pixel(self, data, w, x, y):
        i = (y * w + x) * 3
        if i + 2 < len(data):
            return data[i], data[i+1], data[i+2]
        return 0, 0, 0

    def mouse_move(self, x, y):
        self.hmp('mouse_move {} {}'.format(x, y))
        time.sleep(0.1)

    def mouse_click(self, button=0):
        mask = 1 << button
        self.hmp('mouse_button {}'.format(mask))
        time.sleep(0.05)
        self.hmp('mouse_button 0')
        time.sleep(0.2)

    def mouse_dblclick(self, x, y, button=0):
        self.mouse_move(x, y)
        time.sleep(0.1)
        self.mouse_click(button)
        time.sleep(0.15)
        self.mouse_click(button)
        time.sleep(0.3)


def log(msg):
    print("[LAUNCH] {}".format(msg), flush=True)


def dismiss_dialogs(q):
    """Dismiss any open dialogs/menus."""
    log("Dismissing any open dialogs...")
    q.key('esc', 0.5)
    q.key('esc', 0.5)
    q.key('esc', 0.5)
    time.sleep(0.5)


def open_run_dialog(q):
    """Open Windows 98 Run dialog via Start menu."""
    log("Opening Start menu (Ctrl+Esc)...")
    q.key('ctrl-esc', 2.0)

    # Take screenshot to verify Start menu opened
    q.screenshot('/tmp/ss_start.ppm')
    w, h, d = q.analyze_screen('/tmp/ss_start.ppm')

    # Check for blue Start menu branding strip (RGB ~0,0,123) at left side
    blue_count = 0
    for y in range(400, 740, 10):
        r, g, b = q.pixel(d, w, 20, y)
        if b > 100 and r < 30 and g < 30:
            blue_count += 1
    log("Blue strip pixels: {} (expect >5 for Start menu)".format(blue_count))

    if blue_count < 3:
        log("Start menu may not have opened, retrying...")
        q.key('esc', 0.5)
        time.sleep(0.5)
        q.key('ctrl-esc', 2.0)

    # Navigate to Run: Up (Shut Down), Up (Run), Enter
    log("Navigating to Run...")
    q.key('up', 0.4)   # Shut Down
    q.key('up', 0.4)   # Run
    q.key('ret', 2.0)  # Open Run dialog

    # Verify Run dialog opened - should have a text input area
    q.screenshot('/tmp/ss_run.ppm')
    w, h, d = q.analyze_screen('/tmp/ss_run.ppm')

    # Check center area for dialog (gray background)
    gray_count = 0
    for x in range(300, 700, 20):
        for y in range(300, 500, 20):
            r, g, b = q.pixel(d, w, x, y)
            if 180 < r < 230 and 180 < g < 230 and 180 < b < 230:
                gray_count += 1
    log("Dialog gray pixels: {} (expect >10 for Run dialog)".format(gray_count))
    return gray_count > 5


def launch_via_run(q, game_path):
    """Type path into Run dialog and launch."""
    log("Typing game path: {}".format(game_path))

    # Select all existing text first
    q.key('ctrl-a', 0.2)
    q.key('delete', 0.3)

    # Type the path
    q.typestr(game_path, 0.06)
    time.sleep(0.5)

    # Take screenshot to verify path was typed
    q.screenshot('/tmp/ss_typed.ppm')
    w, h, d = q.analyze_screen('/tmp/ss_typed.ppm')
    # Check if dialog still visible
    r, g, b = q.pixel(d, w, 512, 400)
    log("Center after typing: RGB({},{},{})".format(r, g, b))

    # Press Enter to launch
    log("Pressing Enter to launch...")
    q.key('ret', 5)


def check_game_running(q):
    """Check if game is running by analyzing the screen."""
    q.screenshot('/tmp/ss_game.ppm')
    w, h, d = q.analyze_screen('/tmp/ss_game.ppm')

    # The game typically goes fullscreen or shows intro videos
    # Detect non-desktop state: lots of non-white, non-gray pixels
    non_desktop = 0
    total = 0
    for y in range(0, h, 10):
        for x in range(0, w, 10):
            r, g, b = q.pixel(d, w, x, y)
            total += 1
            # Not white, not gray, not teal (desktop icons)
            if not (r > 200 and g > 200 and b > 200) and \
               not (180 < r < 230 and 180 < g < 230 and 180 < b < 230):
                non_desktop += 1

    pct = non_desktop * 100 // max(total, 1)
    log("Non-desktop pixels: {}% (game if >30%)".format(pct))

    # Sample some key areas
    for label, x, y in [('top-left', 50, 50), ('center', 512, 384),
                         ('bottom', 512, 700), ('taskbar', 512, 750)]:
        r, g, b = q.pixel(d, w, x, y)
        log("  {} ({},{}): RGB({},{},{})".format(label, x, y, r, g, b))

    return pct > 30


def main():
    instance_id = int(os.environ.get('INSTANCE_ID', '0'))
    sock_path = '/tmp/qmp-{}.sock'.format(instance_id)

    log("Connecting to QMP socket: {}".format(sock_path))
    q = QMP(sock_path)
    log("Connected!")

    # Step 1: Dismiss any open dialogs
    dismiss_dialogs(q)

    # Step 2: Open Run dialog
    if not open_run_dialog(q):
        log("WARNING: Run dialog may not have opened, trying anyway...")

    # Step 3: Type the game path using 8.3 short names (no spaces)
    # C:\Program Files -> C:\PROGRA~1
    # LEGO Media -> LEGOME~1
    # Constructive -> CONSTR~1
    # LEGO LOCO -> LEGOLO~1
    game_path = "C:\\PROGRA~1\\LEGOME~1\\CONSTR~1\\LEGOLO~1\\Exe\\Loco.exe"
    launch_via_run(q, game_path)

    # Step 4: Check if game launched
    log("Waiting for game to start...")
    for attempt in range(5):
        time.sleep(3)
        if check_game_running(q):
            log("Game appears to be running!")
            q.s.close()
            return True
        log("Attempt {}: Game not detected yet...".format(attempt + 1))

    # If game didn't launch, try alternative: with quotes around long path
    log("Game may not have launched. Trying with quoted long path...")
    dismiss_dialogs(q)
    if open_run_dialog(q):
        q.key('ctrl-a', 0.2)
        q.key('delete', 0.3)
        # Type with quotes around the path
        alt_path = '"C:\\Program Files\\LEGO Media\\Constructive\\LEGO LOCO\\Exe\\Loco.exe"'
        q.typestr(alt_path, 0.06)
        time.sleep(0.5)
        q.key('ret', 5)

        for attempt in range(5):
            time.sleep(3)
            if check_game_running(q):
                log("Game is running (alt path)!")
                q.s.close()
                return True
            log("Alt attempt {}: Game not detected...".format(attempt + 1))

    log("Game launch failed or undetected")
    q.s.close()
    return False


if __name__ == '__main__':
    success = main()
    sys.exit(0 if success else 1)
