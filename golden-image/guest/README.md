# Guest assets

`LOCOBOOT.BAT` is the boot sentinel. Copy it inside Windows 98 to:

```
C:\WINDOWS\Start Menu\Programs\StartUp\LOCOBOOT.BAT
```

On boot it writes `LOCO_READY` to COM1. The launcher captures COM1 to
`build/run/serial.log`, and `tests/e2e.sh` greps for the marker to confirm the
guest reached a usable state.

No proprietary guest software lives here — only this sentinel and its notes.
