// Board-top testbench for Zen 4: drives clk and btn1 like the board does and checks the LED and UART pins
// Passes when led1 turns on (active low) and led2 stays off; the firmware under test is chosen with the FIRMWARE parameter
`timescale 1 ns / 1 ps

module tb_zen_serv_top;

    // Firmware image to load into the on-chip RAM
    parameter FIRMWARE = "sim/fw/out/selftest.hex";
    // 1 = SERV, 4 = QERV
    parameter WIDTH    = 1;

    // 25 MHz clock into the design (the PLL output on the board)
    reg  clk  = 1'b0;
    // Button 1, active low; released (high) after a short press at the start
    reg  btn1 = 1'b0;
    // LED 1, active low
    wire led1;
    // LED 2, active low
    wire led2;
    // UART transmit pin
    wire uart_tx;

    // Clock generator block: 40 ns period
    always #20 clk = ~clk;

    // Button block: hold reset for 20 clocks, then release
    initial begin
        // Wait 20 clock periods with the button pressed
        repeat (20) @(posedge clk);
        // Release the button
        btn1 = 1'b1;
    end

    // This contains the instantiation for zen_serv_top
    zen_serv_top #(
        .MEMSIZE    (4096),
        .WIDTH      (WIDTH),
        .COMPRESSED (0),
        .FIRMWARE   (FIRMWARE)
    ) dut (
        .clk     (clk),
        .btn1    (btn1),
        .led1    (led1),
        .led2    (led2),
        .uart_tx (uart_tx),
        .uart_tx_rp ()
    );

    // Checker block: waits for the pass LED, fails on the fail LED or a timeout
    initial begin
        // UART idles high before anything is sent
        #1000;
        if (uart_tx !== 1'b1) $display("TEST_FAIL tb_zen_serv_top: uart_tx not idle high");
        // Wait up to 60 ms of simulated time for a verdict
        fork : wait_verdict
            begin
                // Pass LED on
                wait (led1 === 1'b0);
                // Make sure the fail LED is still off
                if (led2 === 1'b0) $display("TEST_FAIL tb_zen_serv_top: led2 lit");
                else $display("TEST_PASS tb_zen_serv_top (led1 lit at %0d us)", $time / 1000);
                disable wait_verdict;
            end
            begin
                // Fail LED on
                wait (led2 === 1'b0);
                $display("TEST_FAIL tb_zen_serv_top: led2 lit at %0d us", $time / 1000);
                disable wait_verdict;
            end
            begin
                // Timeout
                #60000000;
                $display("TEST_FAIL tb_zen_serv_top: timeout");
                disable wait_verdict;
            end
        join
        // Done
        $finish;
    end

endmodule
