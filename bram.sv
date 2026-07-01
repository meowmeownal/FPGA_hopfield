`timescale 1ns / 1ps
import types_pkg::*;

module bram_gen #(
    parameter WIDTH = 40, //bits to djust
    parameter DEPTH = 201 //time evol duration
)
(
    input  logic clk,
    input  logic wr_en, //writing enabled                      
    input  logic [12:0] wr_addr, 
    input  logic signed [WIDTH-1:0] data_in,         
    input  logic [12:0] rd_addr, 
    output logic signed [WIDTH-1:0] data_out         
);

    (* ram_style = "block" *) logic [WIDTH-1:0] y_x [0:DEPTH-1];

    initial begin
    for (int i = 0; i < DEPTH; i++)
        y_x[i] = '0;
    end

    always_ff @(posedge clk) begin
        if (wr_en) begin
            y_x[wr_addr] <= data_in;
        end
        data_out <= y_x[rd_addr]; 
    end

endmodule
