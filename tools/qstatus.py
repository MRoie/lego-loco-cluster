#!/usr/bin/env python3
"""Check QEMU status via QMP."""
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

# Check status
status = q.c('query-status')
print("STATUS:", json.dumps(status, indent=2))

# Check display info
info = q.h('info display')
print("DISPLAY:", json.dumps(info))

# Check if VM is running
vm = q.h('info status')
print("VM STATUS:", json.dumps(vm))

# Check VNC
vnc = q.h('info vnc')
print("VNC:", json.dumps(vnc))

# Try to resume if paused
if status.get('return', {}).get('status') == 'paused':
    print("VM IS PAUSED! Resuming...")
    r = q.c('cont')
    print("RESUME:", json.dumps(r))

q.s.close()
