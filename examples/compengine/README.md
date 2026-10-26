# compengine

Lossless compression experiments for the Vicharak Zen boards: simple hardware-style algorithms (BDI, FPC) against an LZ-style dictionary coder (LZSS), first measured in Python and then run in the FPGA, as a hardware engine (`lzss-engine`) and as C firmware on a PicoRV32 soft CPU (the `lzss` example of PicoRV32-Zen). A PC sends a file through the RP2350's USB port, the RP2350 passes it to the FPGA over the Zen Link, the FPGA compresses it, and the PC checks that the result decompresses back to the original.

**Boards:** `lzss-engine` (the hardware compressor and decompressor) is the board build of this folder and works on the Zen 4 over the Zen Link. The CPU version of the compressor now lives in [PicoRV32-Zen](../PicoRV32-Zen) as `examples/lzss` (built and tested on the Zen 4); `pc-tools/lzss-host.py` is its host tool.

## Layout

```
compengine/
  README.md
  lzss-engine/          hardware LZSS compressor + decompressor in Verilog (no CPU), the current board build
    rtl/  sim/  synth/  lzss-engine.xml  lzss-engine.peri.xml  sdc/  README.md
  pc-tools/             PC side: compengine.py (compress / decompress), lzss_ref.py (Python reference), lzss-host.py (host tool of the CPU build), hw-probe.py,
                        rp-check.py, zink_uart.py (the RP2350 side of the Zen Link), compress.cmd, decompress.cmd, tests/, samples/
  study/                Python measurements (no board needed)
    lossless-codecs.py    real encoders and decoders for BDI, FPC, text-BDI and LZSS; verifies every round trip
    make-test-files.py    turns an image into raw pixel files the codecs can meaningfully test
```

`lzss_ref.py` keeps its underscore because other scripts import it by name.

The board is the Zen 4 (Trion T4F81). A Zen 8 version can be added the same way once that board is brought up.

## What the measurements say

Compressed size as a share of the original (lower is better; 100% = no gain; every codec decompressed back to the exact input, header included):

| Data | BDI | FPC | text-BDI | LZSS (512 B window) | zlib (reference) |
|---|---|---|---|---|---|
| English prose | 100.9% | 109.0% | 89.9% | **59.0%** | 34.5% |
| Verilog source | 100.8% | 105.5% | 89.7% | **32.8%** | 16.8% |
| CSV of readings (text) | 100.9% | 109.4% | 77.7% | **48.5%** | 35.2% |
| int32 sensor readings | **35.2%** | 59.4% | 92.3% | 40.6% | 29.1% |
| int64 pointers near one base | 39.9% | 84.4% | 100.2% | **33.2%** | 23.9% |
| Diagram or screenshot, raw pixels | 71.0% | 63.8% | 70.1% | **29.5%** | 17.5% |
| Photo, raw pixels | 100.8% | 109.1% | 88.4% | 92.1% | 73.5% |
| `.jpg` / `.png` files | 100.9% | 109% | 100.2% | 110–112% | 98–100% |

- BDI and FPC were designed for cache lines of integers and pointers. On text they give nothing, and FPC makes it slightly larger.
- LZSS with a 512-byte window is the reasonable general choice: no tables, no Huffman coding, and it also does well on binary data.
- BDI wins only on slowly varying binary numbers (sensor data).
- Already-compressed files (`.jpg`, `.png`, `.zip`) do not shrink. Use text, source, CSV, or raw pixel dumps. A production version would add a "stored" fallback so the output is never larger than the input plus a small header.

Reproduce: `python study/lossless-codecs.py yourfile.txt` (prints this table for your files plus two synthetic binary sets). For images: `pip install pillow`, `python study/make-test-files.py picture.png`, then pass the `_raw_rgb.bin` file.

## The LZSS format and the CPU firmware

- **Format:** LZSS, 512-byte window. A literal is `0` + 8 bits; a match is `1` + 9 bits (distance - 1) + 4 bits (length - 3), length 3..18. The window carries over between 64-byte blocks; a match never crosses the end of its block; each block's output is padded to a whole byte.
- **Protocol (lock-step, so the 25 MHz CPU never overruns):** PC sends `L` (1..64) then `L` raw bytes; the board replies `C` then `C` compressed bytes. `0` resets the history and is acknowledged with `0`.
- **CPU build:** the firmware, the board top, the pin table, the simulation and the build steps are in `PicoRV32-Zen/examples/lzss` (see its README). It uses about 750 bytes of code and 664 bytes of buffers in the 3 KB RAM, and compressed the 2,402-byte test file to 329 bytes in 0.4 s on the Zen 4.

## Command line (compress / decompress)

Run from `pc-tools` with a Zen Link build loaded; add `--rp COM8` so the data goes through the RP2350 (below). Without `--rp` the tool talks to a USB-serial adapter, which only works with a build that has its UART on header pads (no current build does):

    .\compress FILE            -> writes FILE.lzb next to it, prints sizes, ratio, path, time
    .\decompress FILE.lzb      -> writes FILE (or FILE.restored.ext if FILE exists; never overwrites)

Options: `-o OUT` for the output name, `-p COMx` to pick the adapter port (default: the one CH340 adapter, or env `COMPENGINE_PORT`), `--check-reference` (compress) to compare with the Python encoder, `--force` (decompress) to overwrite `-o`.
Incompressible files are stored (`LZB0`, +8 bytes) instead of growing. Decompress runs on the PC only (no board, no pyserial). Test without hardware: `python3 tests/test-compengine.py`.

    .\decompress FILE.lzb --rp COM8      (decode on the FPGA, checked against the PC's decode; needs the hardware engine build)

### Through the RP2350 (no UART adapter, no wires)

    .\compress FILE --rp COM8

The PC only sends the file and receives the result over the RP2350's own USB port: it sends `[u32 length][file bytes]` and gets the `.lzb` container back. The tool starts a small MicroPython engine on the RP2350 (raw REPL, no files to copy; the Zen Link helper class `pc-tools/zink_uart.py` is sent in front of it, and the board's own `fpga` module does the Zen Link transfers) that cuts the data into 64-byte blocks, runs the block protocol with the FPGA over the Zen Link and streams the container back (so big files never need to fit in RP2350 RAM). The PC only adds the stored fallback for incompressible data and verifies the result by decompressing it. Inside the FPGA the bridge turns the Zen Link bytes into the UART lines of the unchanged compressor, so the byte protocol is the same as before; the old `--rp-uart/--rp-tx/--rp-rx` options are gone because no RP2350 UART pins are used. Rebuild in Efinity, load with `mpremote cp ... :` and `mpremote exec "import main"`, then run compress. Check the Zen Link and the design with `python pc-tools\rp-check.py COM8`. Tested only against a simulated RP2350 (the RP2350 programs run on CPython against a fake Zen Link) and in the Verilog simulation.

## Hardware engine (replaces the CPU build)

`lzss-engine/` holds a Verilog version of the same compressor plus a decompressor (no CPU, 1132 LUTs in Yosys vs 3,113). `lzss-engine/lzss-engine.xml` builds it; see `lzss-engine/README.md`. `--baud` (default 921600, `--baud 115200` for the original rate) now sets the UART rate between the Zen Link bridge and the engine inside the FPGA; it is switched at run time and restored afterwards. The Zen Link itself is the speed limit on the RP2350 side. The CPU version of the compressor is the `lzss` example of PicoRV32-Zen.

## Status and open items

- `lzss-engine` is built in Efinity (including the second PLL output `clk_core`) and works on the Zen 4 over the Zen Link, for both directions. Compress on real files (all decompress back to the input): the 97 KB `picorv32.v` to 36.3% (identical to the Python reference encoder), a 59 KB sensor CSV to 44.4%, README prose to 71.3%, and a 79 KB PNG is stored (+8 bytes). Decode on the FPGA of the same files gives output identical to the PC's decode, at about 25 to 40 KB/s. The PC tool tests pass.
- Decode has a size limit on the RP2350 side: the decoded data comes back faster than it is read, and the bridge's receive FIFO holds 1,023 bytes. `compengine.py` therefore sends at most 7 blocks (448 raw bytes) per group and keeps two groups in flight (at most 910 bytes outstanding). Without that cap, larger files lost bytes on the board (receive overflow flag set in the bridge's STATUS register).
- A run that fails leaves the engine in a bad state, and the next run's first command can fail once. Reset it with `python -m mpremote exec "import fpga; fpga.write(0x10, 1); fpga.write(0x10, 0)"` (or btn1) before the next run.
- The CPU build (`PicoRV32-Zen/examples/lzss`) is built (2,803 of 3,888 logic elements, both clocks meet timing) and works on the Zen 4: `lzss-host.py rp:COM8 test.txt` compressed 2,402 bytes to 329 (plus an 8-byte header) in 0.4 s, identical to the Python reference encoder, and the saved file decompressed back to the input. That test file repeats one sentence, so 14% is not typical; use real prose, source or CSV for realistic ratios (59% / 33% / 49% in the Python study).
- `compress FILE --rp COM8` is for the hardware engine build only; on the CPU build use `lzss-host.py`.
- Still open: throughput with large files on the CPU build (the search slows as the 512-byte window fills), a "stored" fallback for incompressible data, a hash table to speed up matching, and a Zen 8 folder.
