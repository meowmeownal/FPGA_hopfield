`timescale 1ns / 1ps
package types_pkg;


    //14 bitow całkowitych, 18 ulamkowych -> Q14.18 
typedef logic signed [31:0] q8_24_t; //w tej kolejnosic to jest ilosc bitów!!


typedef struct packed { 
    logic signed [31:0] y0;
    logic signed [31:0] y1;
    logic signed [31:0] y2;
    logic signed [31:0] y3;
    logic signed [31:0] y4;
    logic [31:0] dt;
    } DATA; //struc of type DATA
    localparam int TANH_N = 65536;
    localparam int SIN_N = 32768;
    
    parameter logic signed [31:0] TANH_MIN = -32'sd105696461; // -6.3 w formacie Q8.24 
    parameter logic signed [31:0] TANH_MAX =  32'sd105696461;
    
    parameter logic signed [31:0] SIN_MIN = -32'sd52680458; //52707179;
    parameter logic signed [31:0] SIN_MAX = 32'sd52680458;
endpackage 
