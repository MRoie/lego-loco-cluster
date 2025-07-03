#!/usr/bin/env pybricks-micropython
from pybricks.hubs import EV3Brick
from pybricks.parameters import Button
from pybricks.tools import wait
import ujson
import uwebsockets.client as ws
import urequests

# Backend WebSocket for active focus updates
BACKEND_WS = 'ws://localhost:3001/active'
BACKEND_HTTP = 'http://localhost:3001/api/active'

# Ordered list of instance IDs to cycle through
INSTANCES = [
    'instance-0','instance-1','instance-2','instance-3',
    'instance-4','instance-5','instance-6','instance-7','instance-8'
]

brick = EV3Brick()
wsock = ws.connect(BACKEND_WS)
index = 0
hold = 0

# helper to send the currently selected instance
def send_active(id):
    global wsock
    try:
        wsock.send(ujson.dumps({'id': id}))
    except OSError:
        # reconnect and try again
        wsock = ws.connect(BACKEND_WS)
        wsock.send(ujson.dumps({'id': id}))
    try:
        urequests.post(BACKEND_HTTP, json={'ids': [id] if id else []})
    except OSError:
        pass

while True:
    pressed = brick.buttons.pressed()
    if Button.LEFT in pressed:
        index = (index - 1) % len(INSTANCES)
        brick.screen.clear()
        brick.screen.print(INSTANCES[index])
        wait(200)
    elif Button.RIGHT in pressed:
        index = (index + 1) % len(INSTANCES)
        brick.screen.clear()
        brick.screen.print(INSTANCES[index])
        wait(200)
    elif Button.CENTER in pressed:
        hold += 1
        if hold > 10:
            send_active(None)
            brick.screen.clear()
            brick.screen.print('release')
    else:
        if hold:
            send_active(INSTANCES[index])
            brick.screen.clear()
            brick.screen.print('active: ' + INSTANCES[index])
            hold = 0
    wait(80)

