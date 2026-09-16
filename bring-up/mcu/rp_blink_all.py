"""
Zen R4 / R8 -- RP2350B side bring-up.

Same four patterns as zen_blink_all.v, run across the RP2350B GPIOs instead
of the FPGA pins, so both halves of the board are checked identically:

    0  walking one    -- identify each pin individually
    1  walking zero   -- same, inverted (catches stuck-high)
    2  even / odd     -- catches shorts between adjacent pins
    3  all together   -- sync blink / current draw check

SAFE_MODE=True holds the flagged pins static, mirroring the Verilog.

MicroPython on RP2350B:
    mpremote connect /dev/ttyACM0 run zen_rp_blink.py

VERIFY THE PIN GROUPS BELOW against the Zen schematic before running.
Driving a reserved pin can disturb the configured FPGA or fight another
driver on the JTAG / config-SPI nets.
"""

from machine import Pin
import time


# =====================================================================
# PIN GROUPS -- confirm every one of these against the schematic
# =====================================================================

# Onboard RP-driven LEDs (sheet 5: D3 red, D4 blue, D5 green).
# Placeholders -- run sweep() to find the real numbers.
LEDS = {
    "red":   20,
    "green": 21,
    "blue":  22,
}

# GPIOs routed to the J2/J3 headers.
HEADER_GPIOS = [
    6, 7,
    8, 9, 10, 11, 12, 13, 14, 15,
    16, 17, 18, 19, 20, 21, 22, 23,
    34, 35, 36, 37, 38, 39,
    40, 41, 42, 43,          # ADC0..ADC3
    44, 45, 46, 47,
]

# Never drive these. Confirm the GPIO numbers -- the net names in the
# schematic (SPI_CS/SCLK/SO/SI, FPGA_24..29, TCK/TMS/TDI/TDO) do not map
# one-to-one onto GPIO numbers in the extraction.
RESERVED = {
    # FPGA config SPI -- driving these can disturb a configured FPGA
    # 0, 1, 2, 3,            # SPI_CS, SCLK, SO, SI   <- CONFIRM
    # 6-bit interconnect to FPGA
    24, 25, 26, 27, 28, 29,  # FPGA_24..FPGA_29       <- CONFIRM
    # JTAG to FPGA -- multi-drop with J2/J3, contention risk
    # 4, 5,                  # TCK, TMS, TDI, TDO     <- CONFIRM
}

# In the headers list but shared with something else. Held static under
# SAFE_MODE, same idea as FLAGGED in the Verilog.
FLAGGED = {
                      # near SPI_CS / SCLK in schematic  <- CONFIRM
}

SAFE_MODE   = True
ACTIVE_HIGH = True           # LEDs: anode to 3V3 via 1K -> set False
STEP_HZ     = 5              # matches the Verilog default
FORCE_MODE  = None           # None = auto-cycle, 0..3 = lock to one mode


# =====================================================================
def _pins(gpios):
    out = []
    for g in gpios:
        try:
            p = Pin(g, Pin.OUT)
            p.value(0)
            out.append((g, p))
        except Exception as e:
            print("  GPIO{:<3} unavailable ({})".format(g, e))
    return out


def _drive(pins, bits):
    for i, (g, p) in enumerate(pins):
        v = bits[i]
        if SAFE_MODE and g in FLAGGED:
            v = 0
        p.value(v)


def _release(pins):
    for g, p in pins:
        p.value(0)
        p.init(Pin.IN)


def _targets():
    gs = [g for g in HEADER_GPIOS if g not in RESERVED]
    for g in LEDS.values():
        if g not in gs and g not in RESERVED:
            gs.append(g)
    return sorted(gs)


# =====================================================================
# PATTERNS -- one step each, index i of n pins
# =====================================================================
def _walk_one(i, n):
    return [1 if k == i else 0 for k in range(n)]


def _walk_zero(i, n):
    return [0 if k == i else 1 for k in range(n)]


def _even_odd(i, n):
    return [(k ^ i) & 1 for k in range(n)]


def _sync(i, n):
    return [i & 1] * n


PATTERNS = [
    ("walking one",  _walk_one),
    ("walking zero", _walk_zero),
    ("even / odd",   _even_odd),
    ("all together", _sync),
]


def run(mode=None, sweeps=1, gpios=None, verbose=True):
    """
    Run one pattern (mode 0..3) or auto-cycle all four when mode is None.
    Each sweep steps once per pin.
    """
    if mode is None:
        mode = FORCE_MODE
    gpios = gpios if gpios is not None else _targets()
    pins = _pins(gpios)
    n = len(pins)
    if n == 0:
        print("no usable GPIOs")
        return

    modes = range(len(PATTERNS)) if mode is None else [mode]
    d = 1.0 / STEP_HZ

    print("{} GPIOs: {}".format(n, [g for g, _ in pins]))
    if SAFE_MODE and FLAGGED:
        print("SAFE_MODE: holding {} low".format(sorted(FLAGGED)))

    try:
        for m in modes:
            label, fn = PATTERNS[m]
            print("\nmode {} -- {}".format(m, label))
            for _ in range(sweeps):
                for i in range(n):
                    _drive(pins, fn(i, n))
                    if verbose and m == 0:
                        print("  GPIO{}".format(pins[i][0]))
                    time.sleep(d)
    except KeyboardInterrupt:
        print("\nstopped")
    finally:
        _release(pins)


def sweep(dwell=0.6, gpios=None):
    """
    Walk every candidate GPIO, three quick pulses each, printing as it goes.
    Use this to find which GPIO drives which LED, then fill in LEDS above.
    """
    gpios = gpios if gpios is not None else [
        g for g in range(48) if g not in RESERVED
    ]
    print("sweeping {} GPIOs -- watch for LEDs, Ctrl-C to stop\n".format(len(gpios)))
    for g in gpios:
        try:
            p = Pin(g, Pin.OUT)
        except Exception as e:
            print("GPIO{:<3} skip ({})".format(g, e))
            continue
        print("GPIO{}".format(g))
        for _ in range(3):
            p.value(1)
            time.sleep(dwell / 6)
            p.value(0)
            time.sleep(dwell / 6)
        p.init(Pin.IN)
    print("\nsweep done")


def leds(mode=None, sweeps=3):
    """Same patterns, restricted to the onboard LEDs."""
    run(mode=mode, sweeps=sweeps, gpios=sorted(LEDS.values()))


def selftest(forever=True):
    print("=== RP2350B GPIO bring-up ===")
    try:
        while True:
            run(mode=None, sweeps=1, verbose=False)
            if not forever:
                break
    except KeyboardInterrupt:
        print("\nstopped")

if __name__ == "__main__":
    selftest()

