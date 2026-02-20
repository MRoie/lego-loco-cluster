#!/usr/bin/env python3
"""Send VNC keystrokes to open winipcfg in Windows 98 via QEMU's VNC server."""
import socket, struct, time, sys

host = sys.argv[1] if len(sys.argv) > 1 else '127.0.0.1'
port = int(sys.argv[2]) if len(sys.argv) > 2 else 5901

s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.connect((host, port))

# VNC handshake
s.recv(12)
s.send(b'RFB 003.008\n')
s.recv(100)
s.send(struct.pack('B', 1))  # No auth
s.recv(4)
s.send(struct.pack('B', 1))  # Shared
si = s.recv(200)
w, h = struct.unpack('>HH', si[0:4])
print(f'Connected: {w}x{h}')

def key(code, down):
    s.send(struct.pack('>BBxxI', 4, 1 if down else 0, code))

def press(code, delay=0.05):
    key(code, True); time.sleep(delay); key(code, False); time.sleep(delay)

def click(x, y):
    s.send(struct.pack('>BBHH', 5, 1, x, y))
    time.sleep(0.05)
    s.send(struct.pack('>BBHH', 5, 0, x, y))

def type_str(text, delay=0.08):
    for ch in text:
        press(ord(ch), delay)

# Step 1: Click desktop center
click(512, 384)
time.sleep(0.5)
print('Clicked desktop')

# Step 2: Ctrl+Escape -> Start Menu
key(0xffe3, True)   # Ctrl
press(0xff1b)       # Escape
key(0xffe3, False)
time.sleep(1.5)
print('Start Menu opened')

# Step 3: R -> Run dialog
press(ord('r'))
time.sleep(1.5)
print('Run dialog')

# Step 4: Type winipcfg
type_str('winipcfg')
time.sleep(0.3)
print('Typed winipcfg')

# Step 5: Enter
press(0xff0d)
print('Enter pressed')

# Wait for winipcfg to appear
time.sleep(3)

# Click "More Info >>" button to show MAC address
# Winipcfg "More Info" button is typically around x=200, y=250 in the dialog
# But dialog position varies. Let's try the "More Info" button
# The winipcfg dialog is centered, so approximately:
# Dialog ~300x200, centered at 512,384 -> dialog at ~362,284 to ~662,484
# "More Info >>" button is at bottom of the dialog
click(520, 430)
time.sleep(1)
print('Clicked More Info')

s.close()
print('DONE')
