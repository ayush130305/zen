# Hardware LZSS engine (no CPU)

The same compressor as the PicoRV32 firmware, written in Verilog, plus a hardware decompressor. Same byte protocol and same bits for compression, so `compress ... --rp COM8` and the PC tools work unchanged.

**Status:** the RP2350 now reaches this engine over the Zen Link. The compressor RTL (`lzss-hw-top.v`, `lzss-core.v`, ...) is unchanged; the new board top `rtl/lzss-zen4-top.v` puts a Zen Link bridge in front of it. Simulation passes (the engine on its own, and the board top driven by real Zen Link frames, including the baud switch and the stream commands). Built in Efinity 2026.1 for the T4F81: 2,177 / 3,888 logic elements (56%), 1,439 LUT4, 965 flip-flops, 362 adders, 12 RAM blocks; `clk` meets 50 MHz (maximum 54.1 MHz) and `clk_core` meets 25 MHz (maximum 29.3 MHz). Tested on a Zen 4 over the Zen Link: it works. `bitstream/lzss-engine.hex.bin` is that build. Decompression: `decompress FILE.lzb --rp COM8` decodes on the FPGA and checks it against the PC's decode.

## Layout

- `rtl/` `lzss-zen4-top.v` (board top: Zen Link bridge + engine), `lzss-core.v`, `lzss-hw-top.v`, `rx-fifo.v`, `uart-rx.v`, `uart-tx.v`, `zl-uart-bridge.v`, `zl-afifo.v`, `zink/` (Zen Link: `zen-link.v`, `zl-slave.v`, `zl-regs.v`)
- `sim/` `tb-lzss-hw-core.v` (the engine alone over UART lines), `tb-lzss-zink.v` (through the Zen Link), `zink-host-model.vh`, `run-sim.sh` (uses `../../pc-tools/lzss_ref.py` as the reference)
- `synth/` `synth.sh` (Yosys resource report)
- Efinity: `lzss-engine.xml`, `lzss-engine.peri.xml`, `sdc/lzss-engine.sdc`
- `bitstream/` `lzss-engine.hex.bin` (built in Efinity, loads with the board loader)
- The PC tools (`compress`, `decompress`) are in `../pc-tools`.

Protocol: `0` = reset history (reply `0`); `1..64` + bytes = compress a block (reply `C` + `C` bytes); `0x80 | C` + `C` compressed bytes = decode one block (reply `D` + `D` raw bytes). The decoder uses the same 512-byte history window as the encoder, so blocks must be sent in order after a reset.

Host-side limit for decode: the decoded bytes come back faster than the RP2350 reads them, and the bridge's receive FIFO holds 1,023 bytes (`AW_RX = 10`), so a host must never have more than about 900 raw bytes outstanding. `pc-tools/compengine.py` sends at most 7 blocks (448 raw bytes) per `0x7C` group and keeps two groups in flight. A host that sends more loses bytes (sticky receive-overflow bit 3 in the bridge STATUS register).

- `rtl/uart-rx.v`, `rtl/uart-tx.v`: 8N1 UART blocks (CPB = clock cycles per bit, 217 at 25 MHz).
- `rtl/lzss-core.v`: protocol FSM, 1024-byte circular window RAM (written twice so two bytes read per clock), match search at one candidate distance per clock (nearest first, strictly-longer wins), bit-serial token packer, 128-byte output RAM so the block length can be sent first.
- `rtl/lzss-hw-top.v`: engine top level with UART ports (clk, btn1, led1, led2, uart_tx, uart_rx), power-on reset and input synchroniser. Unchanged; `lzss-zen4-top.v` instantiates it and connects uart_tx / uart_rx to the bridge.
- `rtl/lzss-zen4-top.v`: the Zen 4 board top. Two clocks: `clk` 50 MHz for the Zen Link and the bridge registers, `clk_core` 25 MHz for the engine (the same clock as before, so the UART timing is unchanged). The bridge's receive FIFO holds 1024 bytes because the engine answers while the RP2350 is still sending.
- `sim/run-sim.sh`: Icarus testbenches acting as the host; every output byte is compared with `lzss_ref.py` on 10 inputs (1 byte, exactly 64, zeros, repeats, random, text, history wrap, the fake IMU csv), and the hardware decoder must restore each input exactly. Part 1 runs the engine over its UART lines, part 2 runs the board top through real Zen Link frames (block commands, 0x7D / 0x7C stream commands, decode, and the baud switch at 8 and 11 clocks per bit with the return to the default). All pass (about 2.5 minutes).
- `synth/synth.sh`: Yosys `synth_ice40` (4-LUT flow) resource report.

## Yosys result (synth_ice40, flat, CPB = 217, compressor + decompressor + runtime baud switch)

| | hardware engine | PicoRV32 design (Efinity) |
|---|---|---|
| 4-LUTs | 886 (583 for the compressor alone) | 3,113 |
| Flip-flops | 385 | 1,210 |
| Carry cells | 240 | 609 adders |
| Block RAM | 5 x 4 Kb blocks (2 x 1 KB window copies + 128 B output) | 12 x 5 Kb |

The decoder adds about 206 LUTs and no extra RAM. Efinity numbers for the compressor-only build were 617 logic elements (448 LUTs + 112 adders). This is a Yosys estimate for iCE40 (the Efinity numbers would differ slightly; Trion counts carry cells as logic elements).

## Speed

The search tests one distance per clock: about 500 clocks per token at full history, so about 20 us per token at 25 MHz and well above the UART rate. The 115200 UART (11.5 KB/s both ways) is the limit, so a 59 KB file takes about 8 s instead of about 30 s on the CPU version. The link speed can be changed at run time (below), so the UART no longer has to stay the limit.

## Build for the Zen 4 (Efinity)

The project `lzss-engine.xml` builds this engine: top module `lzss_zen4_top`, design files `rtl/*.v` and `rtl/zink/*.v`, the peri file, and the sdc.
1. Open `lzss-engine.xml` in Efinity (reopen it if it is already open). In Interface Designer the PLL needs two output clocks: `clk` 50 MHz (divider 16) and `clk_core` 25 MHz (divider 32). The second output builds and meets timing in Efinity. Compile.
2. From this folder: `python -m mpremote cp bitstream\lzss-engine.hex.bin :` then `python -m mpremote exec "import main"`.
3. From `pc-tools`: `.\compress FILE --rp COM8`. No wires and no copying of Python files are needed: the tool sends its RP2350 program (with the Zen Link helper) itself.
LED 1 is lit while the engine is busy. Pins: clock, btn1, LEDs and the ten Zen Link pads (GPIOL_09, GPIOL_10, GPIOL_00/03/05/07/04/02/01/06); the old `uart_rx` / `uart_tx` pads are now Zen Link data pins. Software reset: `fpga.write(0x10, 1)`. The Zen Link bridge registers are at 0x100.. (see `rtl/zl-uart-bridge.v`). Not yet built or loaded on the board since the move to the Zen Link.

## Baud switching at run time

The design starts at 115200 (217 clocks per bit at 25 MHz). Command `0x7E` + divisor byte (8..255 clocks per bit; smaller values mean the default) answers `0x7E` at the old rate and then both the receiver and transmitter use the new rate. The RP2350 tool then writes the same divisor into the bridge (registers 0x104 / 0x105), so the bridge's bit time follows (divisor 27 for the default 921600, divisor 12 for 2,000,000). If the link is silent for about 0.67 s the engine returns to 115200 and to the command state, so a crashed session never leaves the board stuck. `compengine --baud N` does all of this; the default for `--rp` is 921600 and `--baud 115200` keeps the slow rate. `run-sim.sh` tests divisors 8 and 11, the switch back and the idle fallback.

## Pipelining and the two-lane search

- `rx-fifo.v` (1024 bytes, block RAM) sits between the UART receiver and the core, so the host can send block N+1 while block N is compressing. The RP2350 programs keep one block ahead. The host keeps at most two chunks of 448 bytes ahead.
- The match search reads two candidate distances per clock (a third window RAM copy); the nearer one wins, so the output is still bit-identical to the reference encoder.
- Yosys (iCE40): 1132 LUT4, 9 RAM (with the stream commands below). `run-sim.sh` also runs pipelined and fast-baud pipelined cases.

## Stream commands (the FPGA cuts the blocks)

- `0x7D lo hi` + N raw bytes: the core cuts the data into 64-byte blocks itself and answers `[C][C bytes]` per block (the last block is shorter). The history carries across blocks like before.
- `0x7C lo hi` + M compressed bytes (whole `[C][C bytes]` blocks): the core decodes block after block and answers `[D][D bytes]` per block.
- The RP2350 now only forwards chunks of up to 448 bytes (7 blocks) with a 3-byte header and keeps two chunks in flight. The single-block commands (`1..64`, `0x80|C`) still work and are used by `hw-probe.py` and the UART adapter path.
