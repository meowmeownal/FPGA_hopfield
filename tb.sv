`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 05.04.2026 00:28:32
// Design Name: 
// Module Name: test_bench
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module tb;

logic clk = 0;
logic rst = 1;
logic start = 0;
logic tx;

// clock
always #5 clk = ~clk;

// DUT
top uut (
    .CLK100MHZ(clk),
    .rst_btn(rst),
    .start(start),
    .tx(tx)
);

initial begin
    rst = 0;
    //start = 0;

    repeat (5) @(posedge clk);
    rst = 1;

    repeat (5) @(posedge clk);
   // @(posedge clk);
    start = 1;

    @(posedge clk);
    start = 0;

    //wait (uut.neural_core_inst.state == STOP);
    
    #2000000 $finish;
end

endmodule
