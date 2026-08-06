module blink (
    input  wire clk , // 50 MHz clock
    output  led ,
    output  led2, 
    input wire bt1 , 
    input wire bt2 
);

    assign led = bt1;
    assign  led2 = bt2 ;


endmodule