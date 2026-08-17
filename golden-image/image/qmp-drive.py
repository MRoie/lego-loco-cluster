#!/usr/bin/env python3
"""QMP driver for the image-fix session. Usage: qdrv.py <cmd> [args...]"""
import json, socket, sys, time

def conn():
    s = socket.socket(socket.AF_UNIX); s.settimeout(20); s.connect('/tmp/qmp.sock')
    f = s.makefile('rw'); f.readline()
    s.sendall(b'{"execute":"qmp_capabilities"}\n'); f.readline()
    return s, f

def cmd(s, f, ex, args=None):
    m={'execute':ex}
    if args: m['arguments']=args
    s.sendall((json.dumps(m)+'\n').encode()); return f.readline().strip()

def hmp(s, f, line):
    return cmd(s, f, 'human-monitor-command', {'command-line': line})

def main():
    action = sys.argv[1]
    s, f = conn()
    if action == 'status':
        print(cmd(s, f, 'query-status'))
    elif action == 'dump':
        hmp(s, f, f'screendump /w/{sys.argv[2]}.ppm'); time.sleep(1.5); print('dumped', sys.argv[2])
    elif action == 'key':
        for k in sys.argv[2:]:
            hmp(s, f, f'sendkey {k}'); time.sleep(0.4)
        print('keys sent')
    elif action == 'keyseq':
        # sequence with per-key sleeps: "ctrl-esc:1.5,u:0.5,ret:1"
        for tok in sys.argv[2].split(','):
            k, _, d = tok.partition(':'); hmp(s, f, f'sendkey {k}'); time.sleep(float(d) if d else 0.4)
        print('seq sent')
    elif action == 'mouse':  # x y [button]
        x, y = sys.argv[2], sys.argv[3]; btn = sys.argv[4] if len(sys.argv) > 4 else None
        hmp(s, f, 'mouse_move -5000 -5000'); time.sleep(0.3)
        hmp(s, f, f'mouse_move {x} {y}'); time.sleep(0.5)
        if btn:
            hmp(s, f, f'mouse_button {btn}'); time.sleep(0.2); hmp(s, f, 'mouse_button 0')
        print('mouse done')
    elif action == 'powerdown':
        print(cmd(s, f, 'system_powerdown'))
    elif action == 'wait-shutdown':
        deadline = time.time() + float(sys.argv[2] if len(sys.argv) > 2 else 120)
        while time.time() < deadline:
            r = cmd(s, f, 'query-status')
            if '"status": "shutdown"' in r or '"running": false' in r:
                print('SHUTDOWN', r); return
            time.sleep(2)
        print('TIMEOUT still running')
    else:
        print('unknown', action)

if __name__ == '__main__':
    main()
