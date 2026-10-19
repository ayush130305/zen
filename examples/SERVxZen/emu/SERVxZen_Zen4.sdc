# SERVxZen timing constraints (same clock plan as PicoRV32xZen/Zen4)
# Fabric clock: 25 MHz (PLL 50 MHz x16 / 32). SERV is small and shallow, so a higher PLL output is possible later (raise the multiplier or lower out_divider, then change the period and CLKS_PER_BIT/CLK_HZ together).
create_clock -period 40.000 -name clk [get_ports clk]
# Button and LED pins are asynchronous / slow, so they are not timed against clk.
set_false_path -from [get_ports {btn1}]
set_false_path -to [get_ports {led1 led2}]
