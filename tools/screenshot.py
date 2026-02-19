#!/usr/bin/env python3
"""Take a screenshot and export as BMP, plus detailed pixel analysis."""
import json, socket, time, os, struct

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

iid = int(os.environ.get('INSTANCE_ID', '0'))
q = Q('/tmp/qmp-%d.sock' % iid)

# Check status first
status = q.c('query-status')
running = status.get('return', {}).get('running', False)
st = status.get('return', {}).get('status', 'unknown')
print("VM status: %s, running: %s" % (st, running))

if not running:
    print("VM not running, trying system_reset...")
    q.c('system_reset')
    time.sleep(2)
    r = q.c('cont')
    print("cont result:", json.dumps(r))
    time.sleep(30)  # Wait for boot
    print("Checking status after reset...")
    status2 = q.c('query-status')
    print("Status:", json.dumps(status2.get('return', {})))

# Take screenshot
q.c('screendump', {'filename': '/tmp/ss.ppm'})
time.sleep(1)

with open('/tmp/ss.ppm', 'rb') as f:
    f.readline()  # P6
    line = f.readline()
    while line.startswith(b'#'): line = f.readline()
    w, h = map(int, line.split())
    f.readline()  # 255
    data = f.read()

print("Resolution: %dx%d" % (w, h))

# Convert to BMP
row_size = ((w * 3 + 3) // 4) * 4
bmp_size = 54 + row_size * h

with open('/tmp/screenshot.bmp', 'wb') as f:
    # BMP header
    f.write(b'BM')
    f.write(struct.pack('<I', bmp_size))
    f.write(b'\x00\x00\x00\x00')
    f.write(struct.pack('<I', 54))
    # DIB header
    f.write(struct.pack('<I', 40))
    f.write(struct.pack('<i', w))
    f.write(struct.pack('<i', h))
    f.write(struct.pack('<HH', 1, 24))
    f.write(struct.pack('<I', 0))
    f.write(struct.pack('<I', row_size * h))
    f.write(struct.pack('<iiii', 2835, 2835, 0, 0))
    # Pixel data (bottom-up, BGR)
    for y in range(h - 1, -1, -1):
        row = bytearray()
        for x in range(w):
            i = (y * w + x) * 3
            if i + 2 < len(data):
                row.extend([data[i+2], data[i+1], data[i]])  # BGR
            else:
                row.extend([0, 0, 0])
        while len(row) < row_size:
            row.append(0)
        f.write(bytes(row))

print("BMP saved: /tmp/screenshot.bmp (%d bytes)" % bmp_size)

# Detailed analysis: sample a grid of points
print("\nPixel grid (every 100px):")
for y in range(0, h, 100):
    row_info = "y=%3d:" % y
    for x in range(0, w, 100):
        i = (y * w + x) * 3
        if i + 2 < len(data):
            r, g, b = data[i], data[i+1], data[i+2]
            # Categorize
            if r > 220 and g > 220 and b > 220: c = 'W'
            elif r < 30 and g < 30 and b < 30: c = 'K'  # blacK
            elif r < 50 and g > 90 and b > 90: c = 'T'  # Teal
            elif 180 < r < 230 and abs(r-g) < 10 and abs(r-b) < 10: c = 'G'  # Gray
            elif r > 150 and g < 80 and b < 80: c = 'R'  # Red
            elif r < 80 and g < 80 and b > 150: c = 'B'  # Blue
            elif r > 150 and g > 150 and b < 80: c = 'Y'  # Yellow
            elif g > 100 and g > r + 30 and g > b + 30: c = 'g'  # green
            else: c = '.'  # other
            row_info += " %s" % c
    print(row_info)

# Look for the taskbar (bottom of screen, typically gray/blue)
print("\nTaskbar region (bottom 50px):")
for y in range(max(0, h-50), h, 10):
    colors = []
    for x in range(0, w, 50):
        i = (y * w + x) * 3
        if i + 2 < len(data):
            colors.append("(%d,%d,%d)" % (data[i], data[i+1], data[i+2]))
    print("  y=%d: %s" % (y, ' '.join(colors[:10])))

q.s.close()
print("DONE")
