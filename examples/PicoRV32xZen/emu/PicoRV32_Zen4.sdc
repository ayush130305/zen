# PicoRV32xZen timing constraints
# Fabric clock: 25 MHz (PLL 50 MHz x16 / 32). If P&R misses timing, lower the PLL frequency further (raise out_divider) and the period below.
create_clock -period 40.000 -name clk [get_ports clk]
# Button and LED pins are asynchronous / slow, so they are not timed against clk.
set_false_path -from [get_ports {btn1}]
set_false_path -to [get_ports {led1 led2}]
