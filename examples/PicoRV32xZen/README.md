# PicoRV32xZen

PicoRV32 soft RISC-V CPU (RV32IMC, every optional feature on) with a self-checking firmware that reports over UART.

Tested on the Vicharak Zen 4 board (Efinix Trion T4F81, 3,888 logic elements): built in Efinity, loaded on the board, 9-test self-test passes. The register file is in block RAM, through the wrapper `rtl/picorv32_regs_bram.v`.

## Why the register file is in block RAM

- The stock PicoRV32 keeps its registers in flip-flops with asynchronous reads. On the T4F81 that version needs **5,460 logic elements, but the chip has only 3,888**, so it does not fit.
- The design therefore replaces the register file with two block-RAM copies (`rtl/picorv32_regs_bram.v`, hooked in through the core's `PICORV32_REGS` option). That brings the design to 3,771 / 3,888 and it fits. The cost: the block RAM reads on the falling clock edge, so the register read gets half a clock period and the maximum clock drops to about 29 MHz.
- `rtl/` holds two files (core and wrapper). The wrapper must be analysed before `picorv32.v` in the Efinity project, otherwise the core silently falls back to its flip-flop array.

## Resource usage (Efinity 2026.1, 25 MHz target)

| Board | Register file | LUT4 | Adders | FFs | RAM_5K | Logic elements | Status |
|---|---|---|---|---|---|---|---|
| Zen 4 (T4F81) | with wrapper | 3,111 | 593 | 1,191 | 12 / 15 | **3,771 / 3,888 (97.0%)**, fmax 28.8 MHz | measured, runs on the board |
| Zen 4 (T4F81) | without wrapper | 3,840 | 593 | 2,183 | 6 | 5,460 / 3,888, does not fit | measured earlier, with 1 KB memory |

The Zen 4 "with wrapper" row is the current design (3 KB memory plus UART). The "without wrapper" row is older (1 KB memory, no UART); memory is block RAM, so the LUT count barely changes.

## Layout

```
PicoRV32xZen/
  rtl/   picorv32.v, picorv32_regs_bram.v   (the CPU and the wrapper only)
  sim/   tb_zen_picorv32_top.v, firmware_test.hex        (basic bring-up testbench)
  emu/   everything that runs on the board or tests it
    PicoRV32_Zen4.xml / .peri.xml / .sdc   Efinity project, pins and PLL, clock constraint
    zen_picorv32_top.v                     board top: CPU, 3 KB memory, GPIO, UART pin
    firmware/                              firmware.hex (baked into the bitstream), blink.hex
      selftest/                            C + assembly self-test source and build.sh
    tests/                                 tb_selftest.v, tb_stress.v, gen_stress_fw.py,
                                           run_official_tests.sh
```

Memory map: 3 KB RAM at 0x0 (`MEM_WORDS = 768`, stack top 0xC00), GPIO at 0x1000_0000. The firmware is read with `$readmemh` at synthesis, so every firmware change needs a full Efinity rebuild and a reload.

## Pins

| Port | Pin | Notes |
|---|---|---|
| clk_pad -> PLL -> clk | GPIOL_20 | 50 MHz in, 25 MHz out |
| btn1 | GPIOR_15 | active low, reset |
| led1 | GPIOL_13 | active low, lit = all tests passed |
| led2 | GPIOL_14 | active low, lit = a test failed or the CPU trapped |
| uart_tx | GPIOR_05 (header pad R-05) | 3.3 V, 115200 8N1 |

## Build and load

1. Open `emu/PicoRV32_Zen4.xml` in Efinity and run the full flow. The bitstream is `emu/outflow/PicoRV32_Zen4.hex.bin`.
2. In PowerShell, from `emu`:
   ```
   python -m mpremote cp outflow\PicoRV32_Zen4.hex.bin :
   python -m mpremote exec "print([l for l in open('main.py') if 'FILE_NAME' in l])"
   python -m mpremote exec "import main"
   ```
   `emu/loader_main.py` is the loader that runs on the RP2350 as `main.py`; a fresh board needs it copied over once (`python -m mpremote cp loader_main.py :main.py`).
   If `FILE_NAME` names another file, patch it first, or the old design loads. "Up to date" from `cp` means the board already has that exact file.
3. Wire `R-05` to the RX pin of a USB-serial adapter, join the grounds, and open the port at 115200. The report repeats about every 2 s and ends with `RESULT: ALL PASS`.

To change the firmware: `cd emu/firmware/selftest && bash build.sh`, then copy `selftest.hex` over `emu/firmware/firmware.hex` and rebuild in Efinity. Set `#define DIAG 1` in `selftest.c` for the memory/stack probe build (it skips MUL and DIV to fit).

## Tests (run from the repository root)

Needs Icarus Verilog; the firmware build and the official suite also need `riscv64-unknown-elf-gcc`.

| Test | What it checks | Command |
|---|---|---|
| Basic bring-up | CPU runs a small program, GPIO gets 0x42, no trap | `iverilog -g2012 -o b.vvp sim/tb_zen_picorv32_top.v <rtl> && vvp b.vvp` |
| Self-test + UART | alu, shift, mem, mul, div, flow, counters, rvc, regs; the testbench decodes the UART like a terminal and expects `RESULT: ALL PASS` (about 1 minute) | `iverilog -g2012 -o s.vvp emu/tests/tb_selftest.v <rtl> && vvp s.vvp` |
| Stress | random programs; dumps memory so a wrapper build can be diffed against a stock build | `python3 emu/tests/gen_stress_fw.py <seed>`, then `emu/tests/tb_stress.v` |
| Official suite | upstream PicoRV32 tests (45 instruction tests, mul/div hardware vs software, counters, interrupts) on stock and wrapper, with and without compressed, and single-port | `bash emu/tests/run_official_tests.sh` |

`<rtl>` is the file list, with the wrapper first: `rtl/picorv32_regs_bram.v emu/zen_picorv32_top.v rtl/picorv32.v`

What the self-test covers: ALU ops with edge-case operands, all shifts, byte/half/word memory access, MUL and DIV against software references, branches, calls and loops, cycle and instruction counters, compressed instructions, and every register x1..x31 (a chain written and re-checked, with x0 staying zero). It does not test interrupts; the official suite does.

## Status and open items

- Zen 4: official suite passes on all variants; the full 9-test self-test (alu, shift, mem, mul, div, flow, counters, rvc, regs) passes in simulation and on the board over UART. The earlier diagnostic build's memory and stack probes also matched simulation.
- An earlier hardware-only failure (a data read of address 4 returned 0, a return through the stack restarted the CPU) did not come back after the firmware layout changed. Its root cause was never proven.
- Interrupts are untested on hardware.
