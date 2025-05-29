#!/usr/bin/env pybricks-micropython
from pybricks.hubs import EV3Brick
from pybricks.parameters import Button
from pybricks.tools import wait
import ujson

# lightweight WebSocket client (copy uwebsockets.client to lib/)
import uwebsockets.client as ws       # :contentReference[oaicite:0]{index=0}

BRICK = EV3Brick()

# Map EV3 buttons → loco actions + pod endpoints
TARGETS = {
    Button.UP:    {"url": "ws://192.168.10.81:30081/control", "cmd": "throttle_inc"},
    Button.DOWN:  {"url": "ws://192.168.10.82:30082/control", "cmd": "throttle_dec"},
    Button.LEFT:  {"url": "ws://192.168.10.83:30083/control", "cmd": "brake"},
    Button.RIGHT: {"url": "ws://192.168.10.84:30084/control", "cmd": "horn"},
}

# Keep one socket per target so reconnects are cheap
SOCK = {}

def get_sock(url):
    if url not in SOCK or not SOCK[url].open:
        SOCK[url] = ws.connect(url)
    return SOCK[url]

while True:
    for b in BRICK.buttons.pressed():
        meta = TARGETS.get(b)
        if meta:
            get_sock(meta["url"]).send(ujson.dumps({"cmd": meta["cmd"]}))
    wait(80)          # 12 Hz poll is more than enough
