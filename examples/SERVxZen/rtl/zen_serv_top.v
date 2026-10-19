// Zen 4 (Efinix Trion T4F81) board top for SERVxZen: reset synchroniser, LEDs, UART pin and the generic SERV SoC
// Zen 4 pins: 25 MHz clock, btn1 reset, led1 pass, led2 fail, uart_tx on GPIOR_05
`timescale 1 ns / 1 ps

module zen_serv_top #(
    // RAM size in bytes (power of two); the firmware image, .bss and the stack must fit
    parameter MEMSIZE    = 4096,
    // 1 = SERV (bit-serial), 4 = QERV (4-bit datapath)
    parameter WIDTH      = 1,
    // 1 = enable the C extension (firmware must then be built with rv32ic)
    parameter COMPRESSED = 0,
    // Hex file used to initialise the on-chip memory (relative to the Efinity project folder)
    parameter FIRMWARE   = "firmware/firmware.hex"
) (
    // 25 MHz fabric clock from the PLL (Efinity Interface Designer, same PLL as PicoZen)
    input  wire clk,
    // Button 1, active low: press to reset the CPU
    input  wire btn1,
    // LED 1, active low: lit when the self-test passed (gpio bit 0)
    output wire led1,
    // LED 2, active low: lit when a test failed (gpio bit 1)
    output wire led2,
    // UART transmit pin, idles high; connect to the RX pin of a USB-serial adapter
    output wire uart_tx,
    // Same UART signal on the Zen Link pad GPIOL_03, which is wired to RP2350 GPIO25 (UART1 RX), so the RP2350 can read the report without a USB-serial adapter
    output wire uart_tx_rp
);

    // Reset synchroniser: two flops so the reset releases cleanly on clk
    reg [1:0] rst_sync = 2'b00;
    // GPIO register from the SoC
    wire [7:0] gpio;

    // Reset synchroniser block: shifts the external button level (low while pressed) through two flops
    always @(posedge clk) begin
        // Shift in the button level
        rst_sync <= {rst_sync[0], btn1};
    end

    // LED 1 sinks current, so a 1 in gpio bit 0 turns it on with a low pin
    assign led1 = ~gpio[0];
    // LED 2 sinks current, so a 1 in gpio bit 1 turns it on with a low pin
    assign led2 = ~gpio[1];

    // The RP2350 copy of the UART line
    assign uart_tx_rp = uart_tx;

    // This contains the instantiation for servxzen_soc
    servxzen_soc #(
        .MEMFILE    (FIRMWARE),
        .MEMSIZE    (MEMSIZE),
        .WIDTH      (WIDTH),
        .COMPRESSED (COMPRESSED),
        .SIM        (0),
        .CLK_HZ     (25000000),
        .BAUD       (115200)
    ) u_soc (
        .i_clk     (clk),
        .i_rst     (~rst_sync[1]),
        .o_gpio    (gpio),
        .o_uart_tx (uart_tx)
    );

endmodule
