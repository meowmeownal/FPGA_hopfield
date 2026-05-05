`timescale 1ns / 1ps
package types_pkg;


    //14 bitow całkowitych, 18 ulamkowych -> Q14.18 
typedef logic signed [31:0] q6_26_t; //w tej kolejnosic to jest ilosc bitów!!


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
    
    parameter logic signed [31:0] TANH_MIN = -32'sd422785843; //105696461; // -6.3 
    parameter logic signed [31:0] TANH_MAX =  32'sd422785843;
    
    parameter logic signed [31:0] SIN_MIN = -32'sd210828714; //52707179;
    parameter logic signed [31:0] SIN_MAX = 32'sd210828714;
endpackage 
