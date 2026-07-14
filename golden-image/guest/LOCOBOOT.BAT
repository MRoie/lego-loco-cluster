@ECHO OFF
REM LOCOBOOT.BAT — guest boot sentinel for the golden-image test harness.
REM Place in: C:\WINDOWS\Start Menu\Programs\StartUp\LOCOBOOT.BAT
REM QEMU captures COM1 to build/run/serial.log; the harness greps for LOCO_READY.
MODE COM1:9600,N,8,1 > NUL
ECHO LOCO_READY > COM1
