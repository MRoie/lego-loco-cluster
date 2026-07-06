#!/usr/bin/env python3
"""Reset QEMU VM and wait for it to boot."""
import json, socket, time, os

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

# Check current status
status = q.c('query-status')
print("Current status:", json.dumps(status.get('return', {})))

# Reset the VM
print("Resetting VM...")
r = q.c('system_reset')
print("Reset result:", json.dumps(r))

# Resume if needed
time.sleep(1)
r2 = q.c('cont')
print("Continue result:", json.dumps(r2))

# Wait for boot and take periodic screenshots
for t in [10, 20, 30, 45, 60]:
    print("Waiting %ds..." % t, flush=True)
    time.sleep(t - (10 if t > 10 else 0))
    q.c('screendump', {'filename': '/tmp/ss.ppm'})
    time.sleep(0.5)
    try:
        with open('/tmp/ss.ppm', 'rb') as f:
            f.readline()
            line = f.readline()
            while line.startswith(b'#'): line = f.readline()
            w, h = map(int, line.split())
            f.readline()
            data = f.read()
        # Quick analysis
        cats = {'W':0,'B':0,'O':0}
        for y in range(0, h, 10):
            for x in range(0, w, 10):
                i = (y*w+x)*3
                if i+2 >= len(data): continue
                r,g,b = data[i], data[i+1], data[i+2]
                if r>220 and g>220 and b>220: cats['W'] += 1
                elif r<30 and g<30 and b<30: cats['B'] += 1
                else: cats['O'] += 1
        total = max(sum(cats.values()), 1)
        print("  t=%ds: %dx%d W=%d%% B=%d%% O=%d%%" % (
            t, w, h, cats['W']*100//total, cats['B']*100//total, cats['O']*100//total))
    except Exception as e:
        print("  Screenshot error: %s" % e)

# Final status
status2 = q.c('query-status')
print("Final status:", json.dumps(status2.get('return', {})))

q.s.close()
print("DONE")
