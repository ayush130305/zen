# pwm_demo.py - fade the two LEDs from MicroPython on the Zen board.
# Load the FPGA first (python -m mpremote exec "import main"), then:
#   python -m mpremote run examples/zink_pwm/mcu/pwm_demo.py
import fpga
import utime

# Register addresses used by zink_pwm_top.
LED1, LED2 = 0x10, 0x11

fpga.init()
assert fpga.link_ok(), "link not up: is the FPGA loaded?"

# Fade LED1 up while LED2 fades down, then back, three times.
for _ in range(3):
    for d in list(range(0, 256, 5)) + list(range(255, -1, -5)):
        fpga.write(LED1, d)
        fpga.write(LED2, 255 - d)
        utime.sleep_ms(10)

# Leave both LEDs off.
fpga.write(LED1, 0)
fpga.write(LED2, 0)
print("done")
