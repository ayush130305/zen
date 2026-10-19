# SERVxZen

[SERV](https://github.com/olofk/serv), the award-winning bit-serial RISC-V core, running on the Vicharak Zen 4 board (Efinix Trion T4F81). The repository contains a small SoC around SERV, self-checking firmware, simulation tests and an Efinity project. The test result is read back from the board through the RP2350, so a Zen board and a USB cable are all that is needed.

| | |
|---|---|
| Core | SERV 1.4.0 (tag 2025-10-15, commit `7d9cde4`), RV32I + Zicsr, unmodified |
| Variants | SERV (1-bit datapath) and QERV (4-bit datapath); optional C extension; no M extension |
| Board | Vicharak Zen 4, 25 MHz fabric clock |
| Tools | Efinity 2026.1; Icarus Verilog 12 and `riscv64-unknown-elf-gcc` for simulation |

## Repository layout

```
rtl/
  zen_serv_top.v          Zen 4 board top: reset synchroniser, LEDs, UART pins
  servxzen_soc.v          board-independent SoC: SERV, RAM, GPIO, UART TX, cycle counter, timer
  servxzen_uart_tx.v      memory-mapped UART transmitter
  vendor/serv/            SERV 1.4.0 as released (CPU, servile wrapper, RAM, timer), licence, VERSION
emu/
  SERVxZen_Zen4.xml       Efinity project (.peri.xml pins, .sdc clock)
  firmware/               firmware.hex (the image built into the bitstream), selftest.hex, trapperf.hex
  loader_main.py          loads the bitstream into the FPGA from the RP2350
  rp_listen.py            prints the UART report received by the RP2350
sim/
  tb_soc.v                SoC testbench (UART decoder, result and memory checks)
  tb_zen_serv_top.v       board-top testbench
  run_all.sh              simulation matrix
  mutation_test.sh        breaks the core on purpose and checks the tests notice
  fw/                     firmware source: selftest.c, start.S, link.ld, golden-value generator, build script
```

## Run it on the Zen 4

1. Open `emu/SERVxZen_Zen4.xml` in Efinity and run the full flow (synthesis, place and route, bitstream). The output is `emu/outflow/SERVxZen_Zen4.hex.bin`.
2. From the `emu` folder, copy the bitstream to the board and load it (needs `pip install mpremote`):
   ```
   python -m mpremote cp outflow\SERVxZen_Zen4.hex.bin :SERVxZen_Zen4.hex.bin
   python -m mpremote run loader_main.py
   ```
   `loader_main.py` should print `CDONE = 1`.
3. Read the report:
   ```
   python -m mpremote run rp_listen.py
   ```
   The firmware repeats the report about every 2 s. It ends with `RESULT: ALL PASS`, and LED 1 is lit when all tests passed (LED 2 lights on a failure).

Rebuilding in Efinity does not change what the board runs: the loader reads the bitstream from the RP2350's filesystem, so repeat step 2 after every build.

### Firmware images

The RAM is 4 KB (Zen 4 has 15 RAM_5K blocks), so the tests are split into images. The image is baked into the bitstream through `$readmemh` of `emu/firmware/firmware.hex`; to change it, copy another image over `firmware.hex` and rebuild.

| Image | Checks | Size |
|---|---|---|
| `selftest.hex` (default) | ALU, branches, loads and stores, control flow, CSRs | 3,360 B |
| `trapperf.hex` | ecall, ebreak, misaligned load and store traps, timer interrupt, clocks per instruction | 3,176 B |

Rebuild the firmware with `bash sim/fw/build.sh rv32i_zicsr 4096 selftest` (or `... trapperf "-DWITH_TRAP -DWITH_PERF"`); the hex files appear in `sim/fw/out/`. If a check fails the report prints `FAIL <n> got <hex> exp <hex>`, where `<n>` is the order of the check.

## Results on hardware

Measured on a Zen 4 at 25 MHz.

| Check | Result |
|---|---|
| `selftest` image | ALL PASS, repeated reports clean |
| `trapperf` image | `trap ok`, ALL PASS on repeated passes |

Clocks per instruction (identical to simulation):

| Instruction | SERV | QERV (simulation) |
|---|---|---|
| add | 36.0 | 12.0 |
| shift, slt, branch, jal | 65.7 | 19.2 |
| lw, sw | 67.7 | 21.2 |

At 25 MHz that is 0.69 MIPS for simple ALU instructions and about 0.37 MIPS for shifts, compares, branches and memory accesses. QERV runs the self-test 2.5 times faster in simulation (425,597 vs 1,044,955 clocks).

### Resource use (Efinity 2026.1, T4F81, SERV, no C extension)

| Resource | Used |
|---|---|
| LUT4 | 415 |
| Carry cells (EFX_ADD) | 71 |
| Flip-flops | 280 |
| RAM_5K | 9 of 15 |
| Fmax | 33.5 MHz (25 MHz clock: setup slack 10.2 ns, hold slack 0.6 ns) |

That is roughly 490 of 3,888 logic elements. The CPU itself is only about 265 LUT4; the 32-bit timer is the largest peripheral.

## Memory map

| Address | What |
|---|---|
| `0x0000_0000` | RAM, 4 KB, firmware preloaded; stack at the top |
| `0x4000_0000` | GPIO register: bit 0 = pass (LED 1), bit 1 = fail (LED 2) |
| `0x4000_0004` | UART TX: write a byte to send it; read bit 0 = busy. 115200 8N1 |
| `0x4000_0008` | free-running 32-bit clock counter (read only) |
| `0x8000_0000` | timer: read = mtime, write = mtimecmp (machine timer interrupt) |
| `0x9000_0000` | simulation only: any write ends the simulation |

A hardware UART is used because SERV needs 36 to 68 clocks per instruction, so a bit-banged 115200 baud loop would leave about three instructions per bit at 25 MHz.

## Zen 4 pins

| Port | Pin | Notes |
|---|---|---|
| `clk_pad` | GPIOL_20 | 50 MHz in; PLL gives the 25 MHz fabric clock |
| `btn1` | GPIOR_15 | active low reset |
| `led1` | GPIOL_13 | active low, lit = all tests passed |
| `led2` | GPIOL_14 | active low, lit = a test failed |
| `uart_tx_rp` | GPIOL_03 | UART output wired to RP2350 GPIO25 (UART1 RX); read by `rp_listen.py` |
| `uart_tx` | GPIOR_05 | same UART output on header pad R-05 for a USB-serial adapter |

## Simulation

Needs Icarus Verilog 11 or newer, `riscv64-unknown-elf-gcc`, Python 3 and a bash shell.

```
bash sim/run_all.sh quick      # Zen 4 images and the board top, about 1 minute
bash sim/run_all.sh            # full matrix: SERV/QERV, with and without C extension, about 6 minutes
bash sim/mutation_test.sh      # breaks the core on purpose, expects every mutant to be caught
```

See `sim/README.md` for what is tested and how.

## Limitations

- SERV has no hardware multiply or divide; the simulation-only `full` image does them in software.
- Upstream notes that the decoder is hand-optimised and can misbehave on illegal opcodes, so there is no illegal-instruction test.
- Not yet recorded on hardware: restart with btn1 and a timed long soak.
- Fmax is 33.5 MHz, so there is little headroom to raise the 25 MHz clock.

## Licence

SERV is ISC licensed (`rtl/vendor/serv/LICENSE`); the servile wrapper files carry Apache-2.0 headers.
