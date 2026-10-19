from machine import UART, Pin
import time
u = UART(1, baudrate=115200, tx=Pin(24), rx=Pin(25), rxbuf=4096, timeout=200)
end = time.ticks_add(time.ticks_ms(), 6000)
buf = b""
while time.ticks_diff(end, time.ticks_ms()) > 0:
    d = u.read()
    if d:
        buf += d
if not buf:
    print("NOTHING received on GPIO25")
else:
    print("".join(chr(b) if b in (10, 13) or 32 <= b < 127 else "." for b in buf))
    print("bytes received:", len(buf))
