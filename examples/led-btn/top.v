// ---------------------------------------------------------------------------
// Zen R4 : two LEDs, two buttons, four patterns
//
// Idle behaviour is both LEDs blinking together. btn1 advances the pattern,
// btn2 toggles the speed. Both buttons are debounced and edge-detected.
//
//   pattern 0  sync        both LEDs together        <- default
//   pattern 1  alternate   ping-pong between them
//   pattern 2  offset      same rate, 90 deg apart
//   pattern 3  heartbeat   double-pulse, both together
//
//
// Pins (Zen R4 schematic sheet 5):
//   led1  IOL_13  F1  D4 BLUE  via R34 1K to 3V3   -- active low
//   led2  IOL_14  E2  D5 GREEN via R35 1K to 3V3   -- active low
//   btn1  IOR_15  C9  SW4, switch to GND            -- active low
//   btn2  IOR_16  D7  SW3, switch to GND            -- active low
//
// ---------------------------------------------------------------------------

`default_nettype none

module top #(
    parameter CLK_HZ          = 100_000_000,
    parameter SLOW_HZ         = 2,           // pattern rate, slow
    parameter FAST_HZ         = 8,           // pattern rate, fast
    parameter DEBOUNCE_MS     = 10,
    parameter BTN_ACTIVE_LOW  = 1,
    parameter LED_ACTIVE_HIGH = 0    // D4/D5 sink to the pin: low = lit
) (
    input  wire clk,
    input  wire btn1,        // advance pattern
    input  wire btn2,        // toggle speed
    output wire led1,
    output wire led2
);

    // -----------------------------------------------------------------
    // input synchronisers -- buttons are asynchronous to clk
    // -----------------------------------------------------------------
    reg [2:0] s1 = 3'b000;
    reg [2:0] s2 = 3'b000;

    wire raw1 = BTN_ACTIVE_LOW ? ~s1[2] : s1[2];
    wire raw2 = BTN_ACTIVE_LOW ? ~s2[2] : s2[2];

    always @(posedge clk) begin
        s1 <= {s1[1:0], btn1};
        s2 <= {s2[1:0], btn2};
    end

    // -----------------------------------------------------------------
    // debounce -- output follows input only after it has been stable
    // -----------------------------------------------------------------
    localparam integer DB_RAW   = (CLK_HZ / 1000) * DEBOUNCE_MS;
    localparam integer DB_TICKS = (DB_RAW < 2) ? 2 : DB_RAW;
    localparam integer DB_W     = 20;        // covers 10 ms @ 50 MHz

    reg [DB_W-1:0] c1 = {DB_W{1'b0}};
    reg [DB_W-1:0] c2 = {DB_W{1'b0}};
    reg            d1 = 1'b0;
    reg            d2 = 1'b0;

    always @(posedge clk) begin
        if (raw1 == d1) begin
            c1 <= {DB_W{1'b0}};
        end else if (c1 == DB_TICKS[DB_W-1:0] - 1) begin
            c1 <= {DB_W{1'b0}};
            d1 <= raw1;
        end else begin
            c1 <= c1 + 1'b1;
        end

        if (raw2 == d2) begin
            c2 <= {DB_W{1'b0}};
        end else if (c2 == DB_TICKS[DB_W-1:0] - 1) begin
            c2 <= {DB_W{1'b0}};
            d2 <= raw2;
        end else begin
            c2 <= c2 + 1'b1;
        end
    end

    // rising-edge detect on the debounced level
    reg d1_q = 1'b0;
    reg d2_q = 1'b0;
    always @(posedge clk) begin
        d1_q <= d1;
        d2_q <= d2;
    end

    wire press1 = d1 & ~d1_q;
    wire press2 = d2 & ~d2_q;

    // -----------------------------------------------------------------
    // mode state
    // -----------------------------------------------------------------
    reg [1:0] pattern = 2'd0;                // 0 = both together
    reg       fast    = 1'b0;

    always @(posedge clk) begin
        if (press1) pattern <= pattern + 2'd1;
        if (press2) fast    <= ~fast;
    end

    // -----------------------------------------------------------------
    // time base -- phase[3:0] gives 16 steps per pattern period
    // -----------------------------------------------------------------
    localparam integer DIV_SLOW = CLK_HZ / (SLOW_HZ * 16);
    localparam integer DIV_FAST = CLK_HZ / (FAST_HZ * 16);

    reg [31:0] tick  = 32'd0;
    reg [3:0]  phase = 4'd0;

    wire [31:0] div = fast ? DIV_FAST[31:0] : DIV_SLOW[31:0];

    always @(posedge clk) begin
        if (tick >= div - 1) begin
            tick  <= 32'd0;
            phase <= phase + 4'd1;
        end else begin
            tick <= tick + 32'd1;
        end
    end

    // -----------------------------------------------------------------
    // patterns
    // -----------------------------------------------------------------
    reg a = 1'b0;   // led1
    reg b = 1'b0;   // led2

    always @(posedge clk) begin
        case (pattern)
            2'd0: begin                          // sync -- both together
                a <= phase[3];
                b <= phase[3];
            end
            2'd1: begin                          // alternate -- ping-pong
                a <=  phase[3];
                b <= ~phase[3];
            end
            2'd2: begin                          // offset -- 90 deg apart
                a <= phase[3];
                b <= phase[3] ^ phase[2];
            end
            2'd3: begin                          // heartbeat -- double pulse
                a <= (phase == 4'd0) | (phase == 4'd2);
                b <= (phase == 4'd0) | (phase == 4'd2);
            end
            default: begin
                a <= 1'b0;
                b <= 1'b0;
            end
        endcase
    end

    assign led1 = LED_ACTIVE_HIGH ? a : ~a;
    assign led2 = LED_ACTIVE_HIGH ? b : ~b;

endmodule

`default_nettype wire