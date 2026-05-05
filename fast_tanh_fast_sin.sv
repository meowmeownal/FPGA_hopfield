`timescale 1ns / 1ps
import types_pkg::*;
//typedef logic signed [31:0] q6_26_t;

module fast_tanh(
    input  logic clk,
    input  logic rst,
    input  logic valid_in,
    input  q6_26_t x,

    output logic valid_out,
    output q6_26_t y   
);                                                          
    localparam logic signed [63:0] INV_TANH_RANGE = 64'sd349045984305;          //87261496076;  //(N-1)/tanh_range 
    localparam q6_26_t ONE  =  32'sd67108864;                                   // 16777216;//262144; //1
    localparam q6_26_t MONE = -32'sd67108864;                                   //16777216; //-1

    // LUT-------------
    // (* rom_style = "block" *) q6_26_t tanh_lut [0:TANH_N-1];
    // initial $readmemh("tanh_lut.mem", tanh_lut);

//===============LUT tanh divided in 4 to fit vivado limitations================================ 
    (* rom_style = "block" *) q6_26_t tanh_lut_0 [0:16383];
    (* rom_style = "block" *) q6_26_t tanh_lut_1 [0:16383];
    (* rom_style = "block" *) q6_26_t tanh_lut_2 [0:16383];
    (* rom_style = "block" *) q6_26_t tanh_lut_3 [0:16383];

initial begin
        $readmemh("tanh_lut_low1.mem", tanh_lut_0);
        $readmemh("tanh_lut_low2.mem", tanh_lut_1);
        $readmemh("tanh_lut_high1.mem", tanh_lut_2);
        $readmemh("tanh_lut_high2.mem", tanh_lut_3);
    end
//==============================================================================================

    logic valid_1;
    logic low_1, high_1;
    logic signed [31:0] t_mul;


    always_ff @(posedge clk) begin
        if (rst) begin
            valid_1 <= 0;
            low_1 <= 0;
            high_1 <= 0;
            t_mul <= 0;
        end else begin
            valid_1 <= valid_in;
            low_1  <= (x <= TANH_MIN);
            high_1 <= (x >= TANH_MAX);
            t_mul <= (x - TANH_MIN) ; //* (TANH_N-1); //32+16=48
        end
    end

    logic valid_2;
    logic low_2, high_2;
    logic [15:0] idx;
    logic [25:0] frac;

    logic signed [95:0] t_div; 
    always_ff @(posedge clk) begin
        if (rst) begin
            valid_2 <= 0;
            low_2 <= 0;
            high_2 <=0;
            t_div <= 0;
        end else begin
            valid_2 <= valid_1;
            low_2   <= low_1;
            high_2  <= high_1;
            t_div <= $signed(t_mul) * $signed(INV_TANH_RANGE); //32 + 64 = 96
        end
    end

    logic valid_3;
    logic low_3, high_3;
    always_ff @(posedge clk) begin
        if (rst) begin
            idx<= 0;
            frac <= 0;
        end else begin
            valid_3 <= valid_2;
            low_3   <= low_2;
            high_3  <= high_2;

            idx  <= t_div[67:52];   // int
            frac <= t_div[51:26];    // fractional
        end
    end

    logic valid_4;
    logic low_4, high_4;
    q6_26_t y0, y1;
    logic [25:0] frac_2;

    always_ff @(posedge clk) begin
        if (rst) begin
            valid_4 <= 0;
            y0<=0;
            y1<=0;
            frac_2 <= 0;
            low_4 <= 0;
            high_4 <= 0;
        end else begin
            valid_4 <= valid_3;
            low_4   <= low_3;
            high_4  <= high_3;

            // if (idx >= TANH_N-1) begin
            //     y0 <= tanh_lut[TANH_N-1];
            //     y1 <= tanh_lut[TANH_N-1];
            // end else begin
            //     y0 <= tanh_lut[idx];
            //     y1 <= tanh_lut[idx+1];
            // end


            case (idx[15:14])//2 last bits, (16->14)
                2'b00: y0 <= tanh_lut_0[idx[13:0]]; //max 14 bits
                2'b01: y0 <= tanh_lut_1[idx[13:0]];
                2'b10: y0 <= tanh_lut_2[idx[13:0]];
                2'b11: y0 <= tanh_lut_3[idx[13:0]];
            endcase

            if (idx == 65535) begin 
                y1 <= tanh_lut_3[16383]; //
            end else if (idx[13:0] == 14'h3FFF) begin  //14'h3FFF bits width szerokosc same as 16383 checks if last idx is in next table
                case (idx[15:14])
                    2'b00: y1 <= tanh_lut_1[0]; //go to the next table
                    2'b01: y1 <= tanh_lut_2[0];
                    2'b10: y1 <= tanh_lut_3[0];
                    default: y1 <= tanh_lut_3[16383]; // if its at the end its at the end
                endcase
            end else begin
                case (idx[15:14])
                    2'b00: y1 <= tanh_lut_0[idx[13:0] + 1];
                    2'b01: y1 <= tanh_lut_1[idx[13:0] + 1];
                    2'b10: y1 <= tanh_lut_2[idx[13:0] + 1];
                    2'b11: y1 <= tanh_lut_3[idx[13:0] + 1];
                endcase
            end

                frac_2 <= frac;
         end

    end

    logic signed [31:0] diff;
    logic valid_5;
    logic low_5, high_5;
    logic [25:0] frac_3;

    q6_26_t y0_hold1;
    always_ff @(posedge clk) begin
        if (rst) begin
            valid_5 <= 0;
            diff <= 0;
            low_5 <= 0;
            high_5<=0;
            frac_3 <= 0;
            y0_hold1 <= 0;
        end else begin
            low_5<=low_4;
            high_5<=high_4;
            valid_5 <= valid_4;
            frac_3<= frac_2;
            y0_hold1 <= y0;

            diff <= (y1 - y0); // * frac_2; //32 + 24 =  56

        end 
    end

    logic valid_6;
    logic signed [55:0] diff_2;
    logic low_6, high_6;
    q6_26_t y0_hold2;
    always_ff @(posedge clk) begin
        if(rst)begin
            valid_6 <= 0;
            diff_2 <= 0;
            //y<= 0;
            low_6<=0;
            high_6<=0;
            y0_hold2 <= 0;
        end else begin
            valid_6 <= valid_5;
            low_6<=low_5;
            high_6<=high_5;
            y0_hold2 <= y0_hold1;

            diff_2 <= diff * $signed({1'b0, frac_3}); //diff *frac_2;        
        end
    end


    logic signed [31:0] diff_3;
    logic valid_7;
    logic low_7, high_7;
    q6_26_t y0_hold3;
    always_ff @(posedge clk)begin
        if(rst)begin
            valid_7 <= 0;
            diff_3 <= 0;
            low_7<=0;
            high_7<=0;
            y0_hold3<=0;
        end else begin
            valid_7 <= valid_6;
            low_7<=low_6;
            high_7<=high_6;
            y0_hold3 <= y0_hold2;
            diff_3 <= diff_2 >>>26;
        end
    end

    logic low_8, high_8;
    logic valid_8;
    q6_26_t y0_hold4;
    always_ff @(posedge clk) begin
        if(rst )begin
            valid_8<=0;
            //y <=0;
            low_8 <= 0;
            high_8 <= 0;
            y0_hold4<= 0;
        end else begin
            valid_8 <= valid_7;

            low_8<=low_7;
            high_8<=high_7;
            y0_hold4 <= y0_hold3;
            // if (low_8)
            //     y <= MONE;
            // else if (high_8)
            //     y <= ONE;
            // else
            //     y <= y0 + diff_3;
                // y <= y0 + ((diff_2 + (1 <<< 23)) >>> 24);
        end
    end

    logic low_9, high_9;
    logic valid_9;
    q6_26_t y0_hold5;
    always_ff @(posedge clk) begin
        if(rst )begin
            valid_9<=0;
            low_9 <= 0;
            high_9 <= 0;
            y0_hold5 <= 0;
        end else begin
            valid_9 <= valid_8;
            low_9<=low_8;
            high_9<=high_8;
            y0_hold5 <= y0_hold4;
        end
    end

    logic low_10, high_10;
    logic valid_10;
    q6_26_t y0_hold6;
    always_ff @(posedge clk) begin
        if(rst )begin
            valid_10<=0;
            low_10 <= 0;
            high_10 <= 0;
            y0_hold6 <= 0;
        end else begin
            valid_10 <= valid_9;
            low_10<=low_9;
            high_10<=high_9;
            y0_hold6 <= y0_hold5;
        end
    end

    logic low_11, high_11;
    logic valid_11;
    q6_26_t y0_hold7;
    always_ff @(posedge clk) begin
        if(rst )begin
            valid_11<=0;
            low_11 <= 0;
            high_11 <= 0;
            y0_hold7 <= 0;
        end else begin
            valid_11 <= valid_10;
            low_11<=low_10;
            high_11<=high_10;
            y0_hold7 <= y0_hold6;
        end
    end

    logic low_12, high_12;
    logic valid_12;
    q6_26_t y0_hold8;
    always_ff @(posedge clk) begin
        if(rst )begin
            valid_12<=0;
            low_12 <= 0;
            high_12 <= 0;
            y0_hold8 <= 0;
        end else begin
            valid_12 <= valid_11;
            low_12<=low_11;
            high_12<=high_11;
            y0_hold8 <= y0_hold7;
        end
    end

    logic low_13, high_13;
    q6_26_t y0_hold9;
    always_ff @(posedge clk) begin
        if(rst )begin
            valid_out<=0;
            low_13 <= 0;
            high_13 <= 0;
            y <= 0;
            y0_hold9 <= 0;
        end else begin
            valid_out <= valid_12;
            low_13<=low_12;
            high_13<=high_12;
            y0_hold9 <= y0_hold8;

            if (low_13)
                y <= MONE;
            else if (high_13)
                y <= ONE;
            else
                y <= y0_hold9 + diff_3;
        end
    end

    // initial begin
    //     $display("tanh_lut[0]=%f", real'(tanh_lut_0[0]) / 67108864.0);
    //     $display("tanh_lut[1]=%f", real'(tanh_lut_0[1])/67108864.0);
    //     $display("tanh_lut[(TANH_N-1)/4]=%f", real'(tanh_lut_0[16383])/67108864.0);
    //     $display("tanh_lut[TANH_N-1]=%f", real'(tanh_lut_3[16383])/67108864.0);
    // end


    
    // logic [7:0] latency_counter;
    // logic first_output_done;

    // int latency_count = 0;
    // logic measuring = 0;

    // always_ff @(posedge clk) begin
    //     if (rst) begin
    //         latency_count <= 0;
    //         measuring <= 0;
    //         first_output_done <=0;
    //     end else begin
    //         if (valid_in && !measuring && !first_output_done) begin
    //             measuring <= 1;
    //             latency_count <= 1; 
    //         end 
    //         else if (measuring && !valid_out) begin
    //             latency_count <= latency_count + 1;
    //         end 
    //         else if (measuring && valid_out) begin
    //             $display("--- LATENCY MEASURE FOR TANH ---");
    //             $display("clock cycles: %0d ", latency_count);
    //             $display("-----------------------");
    //             measuring <= 0;
    //             first_output_done <= 1;
    //         end
    //     end
    // end


endmodule


//-------------MODULLE FAST SIN____________________________
module fast_sin(
    input  logic clk,
    input  logic rst,
    input  logic valid_in,
    input  logic signed [31:0] x,   //24 bit q6.18

    output logic valid_out,
    output q6_26_t y 
);

    (* rom_style = "block" *) q6_26_t sin_lut [0:SIN_N-1];
    initial begin
        $readmemh("sin_lut.mem", sin_lut);
    end
    
    logic signed [63:0] mult1;
    logic signed [31:0] k;
    //q6_26_t x_red; //32
    logic signed [31:0] x_red;

    logic valid_pi1, valid_pi2, valid_pi3, valid_pi4;

    localparam q6_26_t TWO_PI = 32'sd421657428; //105414357;     
    localparam q6_26_t INV_TWO_PI = 32'sd10680707; //2670177; 
    localparam logic signed [63:0] INV_SIN_RANGE = 64'sd349974740388; //87493685097 ; 
    logic signed [63:0] x_tmp;
    logic signed [31:0] x_pi1, x_pi2;


    always_ff @(posedge clk) begin
        if (rst) begin
            valid_pi1 <= 0;
            mult1 <= 0;
        end else begin
            //==========etap 1================================
            valid_pi1 <= valid_in;
            mult1 <= x * INV_TWO_PI; //32 + 32 = 64bit
            x_pi1 <= x;
            //=================================================
        end 
    end

        always_ff @(posedge clk) begin
            if(rst) begin 
                valid_pi2 <= 0;
                k <= 0;
            end else begin
                valid_pi2 <= valid_pi1;
            //========etap2=======================================
            //k <= (mult2 + (1<<17)) >>> 18; //to zaokragla
            k <= mult1 >>> 52; //k <= mult1 >>> 18; //to zaokragla w dol, czyli bardziej modulo
            x_pi2 <= x_pi1;
            //=====================================================
            end
        end

        always_ff @ (posedge clk) begin
            if(rst) begin
                valid_pi3 <= 0;
                x_tmp <= 0;
            end else begin
                valid_pi3 <= valid_pi2;
            //=================etap 3==============================
            x_tmp <= x_pi2 - ($signed(k) * $signed(TWO_PI)); //32 + 32 = 64
            //====================================================
            end
        end

        logic signed [31:0] x_tmp32;
        assign x_tmp32 = x_tmp;

        always_ff @(posedge clk) begin
            if(rst) begin
                valid_pi4 <= 0;
                x_red <= 0;
            end else begin
                valid_pi4 <= valid_pi3;

            //==========================etap4============================
            if (x_tmp32 > SIN_MAX) x_red <=  (x_tmp32 - TWO_PI);
            else if (x_tmp32 < SIN_MIN) x_red <= (x_tmp32 + TWO_PI); 
            else x_red <= x_tmp32; 
        end
    end



    logic [14:0] idx;     
    logic [25:0] f_1; 
    //---------changed bits from 31 to 64---------
    logic signed [31:0] t_mul;
    //logic signed [63:0] t_mul;
    //---------------changed from 64 to 96: -------------------
    logic signed [95:0] t_div;
    //--------------------------------

    logic valid_1;

    always_ff @(posedge clk) begin
        if (rst) begin
            valid_1 <= 0;
            t_mul <= 0;
        end else begin
            valid_1 <= valid_pi4;
            t_mul <= (x_red - SIN_MIN);  //32 + 16

        end
    end

    logic valid_op1, valid_op2;
    always_ff @(posedge clk) begin
        if(rst) begin
            valid_op1 <= 0;
            t_div <= 0;
        end else begin
            valid_op1 <= valid_1;
            t_div <= (t_mul)  *INV_SIN_RANGE;  //32 + 64
        end

    end

    always_ff @(posedge clk)begin
        if(rst) begin
            valid_op2 <= 0;
            idx <= 0;
            f_1 <= 0;
        end else begin
            valid_op2 <=  valid_op1;
            idx <= t_div[66:52];
            f_1 <= t_div[51:26];
        end
    end

    logic [14:0] i_safe;
    
//-------------making sure inex not outside of range ---------
    always_comb begin
        if (idx >= SIN_N-1)
            i_safe = SIN_N-1; 
        else
            i_safe = idx;
    end
//-----------------------------------------------------------

//----------------------LUT----------------
    q6_26_t y0, y1;
    logic [25:0] f_2;
    logic valid_2;

        always_ff @(posedge clk) begin
            if(rst) begin
                valid_2 <= 0;
                y0 <= 0;
                y1 <= 0;
                f_2 <= 0;
            end else  begin
                valid_2 <= valid_op2;
                y0 <= sin_lut[i_safe]; //sin_lut[i_1];

                if (i_safe == SIN_N-1)
                    y1 <= sin_lut[i_safe]; //sin_lut[i_1];
                else
                    y1 <= sin_lut[i_safe+1];//sin_lut[i_1+1];
                f_2 <= f_1;
            end
        end

//----------------------INTERPOLACJA---------
        logic signed [31:0] diff;
        logic signed [31:0] y_interpol;
        logic valid_3;
        logic [25:0] f_3;

        q6_26_t y0_hold1, y0_hold2, y0_hold3;

        always_ff @(posedge clk) begin
            if(rst)begin
                valid_3<=0;
                diff<=0;
                y0_hold1 <= 0;
                f_3 <= 0;
            end else begin
                valid_3 <= valid_2;
                y0_hold1 <= y0; 
                diff <= $signed(y1) - $signed(y0); // <= (y1-y0); 
                f_3 <= f_2;
            end
            
        end

        logic signed [63:0] diff_2;
        logic valid_4;
        always_ff @(posedge clk) begin
            if(rst)begin
                valid_4<=0;
                diff_2<=0;
                y0_hold2 <= 0;
            end else begin
                valid_4 <= valid_3;
                y0_hold2 <= y0_hold1;
                diff_2 <= diff* $signed({1'b0, f_3}); //f_3;
            end
        end


        logic signed [31:0] diff_3;
        logic valid_5;
        always_ff @(posedge clk) begin
            if(rst)begin
                valid_5<=0;
                diff_3<=0;
                y0_hold3 <= 0;
            end else begin
                valid_5 <= valid_4;
                y0_hold3 <= y0_hold2;
                diff_3 <= 32'(diff_2 >>> 26); //diff_2>>>24;
            end
        end


        logic valid_6;
        always_ff @(posedge clk) begin
            if(rst)begin
                valid_out<=0;
                y <= 0;
                //y_interpol <= 0;
            end else begin
                valid_out <= valid_5;
                y <= y0_hold3 + diff_3;
            end
        end

        // assign y = y_interpol;

    //     initial begin
    //     $display("sin_lut[0]=%f", real'(sin_lut[0]) / 67108864.0);
    //     $display("sin_lut[1]=%f", real'(sin_lut[1])/67108864.0);
    //     $display("sin_lut[(SIN_N-1)/4]=%f", real'(sin_lut[(SIN_N-1)/4])/67108864.0);
    //     $display("sin_lut[SIN_N-1]=%f", real'(sin_lut[SIN_N-1])/67108864.0);
    // end

    // logic [7:0] latency_counter;
    // logic first_output_done;

    // int latency_count = 0;
    // logic measuring = 0;

    // always_ff @(posedge clk) begin
    //     if (rst) begin
    //         latency_count <= 0;
    //         measuring <= 0;
    //         first_output_done <=0;
    //     end else begin
    //         if (valid_in && !measuring && !first_output_done) begin
    //             measuring <= 1;
    //             latency_count <= 1; 
    //         end 
    //         else if (measuring && !valid_out) begin
    //             latency_count <= latency_count + 1;
    //         end 
    //         else if (measuring && valid_out) begin
    //             $display("--- LATENCY MEASURE FOR SIN ---");
    //             $display("clock cycles: %0d ", latency_count);
    //             $display("-----------------------");
    //             measuring <= 0;
    //             first_output_done <= 1;
    //         end
    //     end
    // end
    
endmodule
