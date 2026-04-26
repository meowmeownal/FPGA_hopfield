`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
//sprawdz, czy DOBRZE SA INTERPOLOWANE FUNKCJE JAKIES Z PALACA DAJE, STWORZ INSTANCJE GDZIE DAJESZ JAKIES LICZBY I SPR, CZY DOBRZE WYPLUWA
// 
//////////////////////////////////////////////////////////////////////////////////



import types_pkg::*;

module neural_core #(
    parameter T = 50 //mozna bedzie zwiekszyc :))
)(
    input  logic clk,
    input  logic rst,
    input  logic start,

    output logic sample_send,
    output DATA sample_out
);

localparam logic [7:0] ADDR  = 8'h60 << 1;
localparam logic [7:0] ADDR1 = 8'h61 << 1;
localparam int N = 5; //liczba neuronow

//logic signed [47:0]
    (* rom_style = "block" *) q8_24_t  bg_lut [0:5000];
    initial begin
        $readmemh("bg_lut.mem", bg_lut);
    end
    //---------------------------------------------------------------------------

    q8_24_t y0  [0:T];
    q8_24_t y1  [0:T];
    q8_24_t y2  [0:T];
    q8_24_t y3  [0:T];
    q8_24_t y4  [0:T];

    logic signed [55:0] y0_sum [0:T];
    logic signed [55:0]  y1_sum [0:T];
    logic signed [55:0]  y2_sum [0:T];
    logic signed [55:0]  y3_sum [0:T];
    logic signed [55:0]  y4_sum [0:T];

    // logic signed [55:0] y0_hold, y1_hold, y2_hold, y3_hold, y4_hold;

initial begin
    y0[0] = 32'sd13421773; ///0.8
    y1[0] = 32'sd5033165;  //0.3
    y2[0] = 32'sd6710886;  //0.4
    y3[0] = 32'sd10066330;  //0.6
    y4[0] = 32'sd11744051; //0.7
end 

initial begin
    for (int i = 1; i <= T; i++) begin
        y0[i] = 0;
        y1[i] = 0;
        y2[i] = 0;
        y3[i] = 0;
        y4[i] = 0;
    end
end

initial begin
    for (int i = 0; i <= T; i++) begin
        y0_sum[i] = 0;
        y1_sum[i] = 0;
        y2_sum[i] = 0;
        y3_sum[i] = 0;
        y4_sum[i] = 0;
    end
end


logic [12:0] om;

logic [12:0] r;

logic signed [55:0] acc0, acc1, acc2, acc3, acc4; //do przechowywania w danej chwili wartosci neuronow

q8_24_t tanh_y0_reg, tanh_y1_reg, tanh_y2_reg, tanh_y3_reg, tanh_y4_reg;
q8_24_t sin_y0_reg,  sin_y1_reg,  sin_y2_reg,  sin_y3_reg,  sin_y4_reg;

// logic valid_tanh0_reg, valid_tanh1_reg, valid_tanh2_reg, valid_tanh3_reg, valid_tanh4_reg;
// logic valid_sin0_reg,  valid_sin1_reg,  valid_sin2_reg,  valid_sin3_reg,  valid_sin4_reg;

q8_24_t pipe_y0, pipe_y1, pipe_y2, pipe_y3, pipe_y4;

q8_24_t current_y0;
q8_24_t current_y1;
q8_24_t current_y2;
q8_24_t current_y3;
q8_24_t current_y4;


//---------------WEIGHTS MATRIX----------------------------------
q8_24_t weights [0:N-1][0:N-1];
initial begin
    weights[0][0] = 32'sd0;
    weights[0][1] = -32'sd5033165;   // -3.0 * 2^24
    weights[0][2] = -32'sd13421773;  // -0.8
    weights[0][3] = -32'sd10066330;  // -0.6
    weights[0][4] = 32'sd0;

    weights[1][0] = -32'sd50331648;  // -3.0
    weights[1][1] = 32'sd0;
    weights[1][2] = 32'sd33554432;   // 2.0
    weights[1][3] = 32'sd0;
    weights[1][4] = 32'sd6710886;   // 0.4

    
    weights[2][0] = 32'sd28521267; //1.7
    weights[2][1] = -32'sd6710886;  //-0.4
    weights[2][2] = 32'sd50331648;  //3.0
    weights[2][3] = 32'sd0;
    weights[2][4] = 32'sd0;

    
    weights[3][0] = 32'sd11744051; //0.7
    weights[3][1] = 32'sd0;
    weights[3][2] = 32'sd0;  
    weights[3][3] = 32'sd0;
    weights[3][4] = 32'sd0; 

    
    weights[4][0] = 32'sd0;  //0
    weights[4][1] = 32'sd28521267; //1.7
    weights[4][2] = 32'sd0;   // 0
    weights[4][3] = 32'sd0;
    weights[4][4] = 32'sd0; 

end
//---------------------------------------

typedef enum logic [4:0] {
    WAIT, 
    INIT, 
    INIT_WAIT_TO_SEND,
    SEND_NEURONS,
    WAIT_ONE_RESULT,
    LATCH_RESULT,
    INIT_OM, // 
    //WAIT_PIPE,
    INIT_PIPE_MUL1, //
    INIT_PIPE_MUL2,
    INIT_PIPE_G1G2,
    INIT_GSINGTANH,
    INIT_GSINGTANH_SHIFT,
    INIT_PIPE_SUM,
    MUL_ACC,
    SHIIFT,
    LOOP_R, //r iterations
    FINALIZE,
    OM_START,
    OM_WAIT_TO_SEND,
    OM_START2,
    OM_WAIT_ONE,
    OM_LATCH,
    //OM_WAIT,
    OM_SUM,
    OM_G1G2,
    OM_GSINGTANH,
    OM_GSINGTANH_SHIFT,
    OM_MUL1,
    OM_MUL2,
    SEND, //wysylanie do fifo
    STOP
} state_t;

state_t state; 


//---------------------------------------

localparam TANH_LATENCY = 12;  //tanh delay
localparam SIN_LATENCY  = 12;  

logic start_pipe;
logic [2:0] neuron_num; 

q8_24_t neuron_in;
always_comb begin
    case(neuron_num)
        3'd0: neuron_in = current_y0; 
        3'd1: neuron_in = current_y1; 
        3'd2: neuron_in = current_y2; 
        3'd3: neuron_in = current_y3; 
        3'd4: neuron_in = current_y4; 
        default: neuron_in = 0;
    endcase
end

q8_24_t tanh_out, sin_out;
logic valid_tanh, valid_sin;

fast_tanh th (
    .clk(clk),
    .rst(rst),
    .valid_in(start_pipe),
    .x(neuron_in),
    .valid_out(valid_tanh),
    .y(tanh_out)
);

fast_sin s (
    .clk(clk),
    .rst(rst),
    .valid_in(start_pipe),
    .x(neuron_in),
    .valid_out(valid_sin),
    .y(sin_out)
);

//----------------------

// q8_24_t dupa = 32'sd7214203;
// logic start_test;
// q8_24_t tanh_out_test, sin_out_test;
// logic valid_sin_test, valid_tanh_test;


// fast_tanh th_test (
//     .clk(clk),
//     .rst(rst),
//     .valid_in(start_test),
//     .x(dupa),
//     .valid_out(valid_tanh_test),
//     .y(tanh_out_test)
// );

// fast_sin s_test (
//     .clk(clk),
//     .rst(rst),
//     .valid_in(start_test),
//     .x(dupa),
//     .valid_out(valid_sin_test),
//     .y(sin_out_test)
// );

// logic [3:0] cnt;
// always_ff @(posedge clk) begin
//     if (rst) begin
//         cnt <= 0;
//         start_test <= 0;
//     end else begin
//         start_test <= 1;
//         cnt <= cnt + 1;

//         if (cnt == 5) begin
//              $display("tanh(0.5) = %h, real = 0.462 , sin(0.5) = %h, real is 0.479",tanh_out_test, sin_out_test );
//         end
//     end
// end


//-------------------------------------
logic signed [63:0] m01, m02, m03;
logic signed [63:0] m10, m12, m14;
logic signed [63:0] m20, m21, m22;
logic signed [63:0] m30;
logic signed [63:0] m41;

logic signed [39:0] m01_shift, m02_shift, m03_shift;
logic signed [39:0] m10_shift, m12_shift, m14_shift;
logic signed [39:0] m20_shift, m21_shift, m22_shift;
logic signed [39:0] m30_shift;
logic signed [39:0] m41_shift;

logic signed [79:0] mul_0, mul_1, mul_2, mul_3, mul_4;
logic signed [55:0] scaled_0, scaled_1, scaled_2, scaled_3, scaled_4;

q8_24_t f1 = 32'sd0;
q8_24_t f3 = 32'sd0;
q8_24_t a1 = -32'sd36909875;  //-2.2
q8_24_t a2 = 32'sd50331648;  //changing that 3.0
q8_24_t a3 = 32'sd20132659; //1.2

logic signed [39:0] tmp1_shift, tmp2_shift;
logic signed [63:0] tmp1, tmp2;
logic signed [47:0] G1tanh, G2sin; 
logic signed [39:0] G1r0, G2r0;
logic signed [71:0] G1_tmp, G2_tmp;

always_comb begin
    if(state inside {OM_START, OM_WAIT_TO_SEND, OM_START2, OM_MUL1, OM_MUL2, OM_SUM, OM_GSINGTANH, OM_G1G2, OM_LATCH, OM_WAIT_ONE})begin //(om > 0 && om <= T) begin // OM_WAIT,
        current_y0 = y0[om];
        current_y1 = y1[om];
        current_y2 = y2[om];
        current_y3 = y3[om];
        current_y4 = y4[om];

    end else begin //if (om == 0)begin  //

        current_y0 = y0[0];
        current_y1 = y1[0];
        current_y2 = y2[0];
        current_y3 = y3[0];
        current_y4 = y4[0];
    end
end


logic [3:0] wait_cnt;

always_ff @(posedge clk) begin
    if (rst) begin
        om <= 0;
        r <= 0;
        sample_send <= 0;
        start_pipe <= 0;
        wait_cnt <= 0;

        tmp1 <= 0; 
        tmp2 <= 0; 
        tmp1_shift <= 0;
        tmp2_shift <= 0;
        G1r0 <= 0;
        G2r0 <= 0;
        G2sin <= 0;
        G1tanh <= 0;
        G1_tmp <= 0; 
        G2_tmp <= 0; 

        m01 <= 0;
        m02 <= 0;
        m03 <= 0;
        m10 <= 0;
        m12 <= 0;
        m14 <= 0;
        m20 <= 0;
        m21 <= 0;
        m22 <= 0;
        m30 <=0;
        m41 <= 0;

        m01_shift <= 0;
        m02_shift <= 0;
        m03_shift <= 0;
        m10_shift <= 0;
        m12_shift <= 0;
        m14_shift <= 0;
        m20_shift <= 0;
        m21_shift <= 0;
        m22_shift <= 0;
        m30_shift <=0;
        m41_shift <= 0;

        tanh_y0_reg <= 0;
        tanh_y1_reg <= 0;
        tanh_y2_reg <= 0;
        tanh_y3_reg <= 0;
        tanh_y4_reg <= 0;

        sin_y0_reg <= 0;
        sin_y1_reg <= 0;
        sin_y2_reg <= 0;
        sin_y3_reg <= 0;
        sin_y4_reg <= 0;

        state <= WAIT;

    end else begin
        sample_send <=0;
        case (state)

        WAIT:
            if(start) state <=INIT;
        INIT: begin

            neuron_num <= 0;
            start_pipe <= 0;//1;

            state <= INIT_WAIT_TO_SEND;
        end 

        INIT_WAIT_TO_SEND: begin
            start_pipe <= 1;
            state <= SEND_NEURONS;
        end

        SEND_NEURONS: begin
            start_pipe <= 1;
            wait_cnt <= 0;
            state <= WAIT_ONE_RESULT;
        end


        WAIT_ONE_RESULT: begin
            start_pipe <= 0;
            wait_cnt <= wait_cnt +1;
            if(wait_cnt == SIN_LATENCY -1) begin  //-2
                state <= LATCH_RESULT;
            end
        end

        LATCH_RESULT: begin
            case(neuron_num)
            0: begin tanh_y0_reg<=tanh_out; sin_y0_reg<=sin_out; end
            1: begin tanh_y1_reg<=tanh_out; sin_y1_reg<=sin_out; end
            2: begin tanh_y2_reg<=tanh_out; sin_y2_reg<=sin_out; end
            3: begin tanh_y3_reg<=tanh_out; sin_y3_reg<=sin_out; end
            4: begin tanh_y4_reg<=tanh_out; sin_y4_reg<=sin_out; end
        endcase

        if (neuron_num == 4) begin
            neuron_num <= 0;
            state <= INIT_PIPE_MUL1; 
            
        end else begin
            neuron_num <= neuron_num + 1;
            state <= SEND_NEURONS;
        end
    end
//-------------------------------------------------------------------------------

        INIT_PIPE_MUL1: begin

            tmp1 <= (a1) * (tanh_y2_reg);
            tmp2 <= (a3) * (sin_y4_reg);

            m01 <= (weights[0][1]) * (tanh_y1_reg);
            m02 <= (weights[0][2]) * (sin_y2_reg);
            m03 <= (weights[0][3] * sin_y3_reg);

            m10 <= (weights[1][0]) * (sin_y0_reg);
            m12 <= (weights[1][2]) * (sin_y2_reg);
            m14 <= (weights[1][4]) * (sin_y4_reg);

            m20 <= (weights[2][0]) * (tanh_y0_reg); 
            m21 <= (weights[2][1]) * (tanh_y1_reg);
            m22 <=  (weights[2][2]) * (sin_y2_reg);

            m30 <= (weights[3][0]) * (tanh_y0_reg);

            m41 <= (weights[4][1]) * (tanh_y1_reg);

            state<= INIT_PIPE_MUL2;
       end

       INIT_PIPE_MUL2: begin 

            tmp1_shift <= (tmp1 ) >>> 24;
            tmp2_shift <= (tmp2 ) >>> 24;

            m01_shift <= (m01 ) >>> 24;  //40 -> Q16.24
            m02_shift <= (m02 ) >>> 24; 
            m03_shift <= (m03 ) >>> 24;

            m10_shift <= (m10 ) >>> 24; 
            m12_shift <= (m12 ) >>> 24; 
            m14_shift <= (m14 ) >>> 24; 

            m20_shift <= (m20 ) >>> 24; 
            m21_shift <= (m21 ) >>> 24;
            m22_shift <=  (m22 ) >>> 24;

            m30_shift <= (m30 ) >>> 24;

            m41_shift <= (m41 ) >>> 24;


        state <= INIT_PIPE_G1G2; 
       end

       
       INIT_PIPE_G1G2: begin   

        //  $display("a1 = %f, tanh[y2] = %f, y2[om] = %f, tmp1 = %f\n", real'(a1)/16777216.0, real'(tanh_y2_reg)/16777216.0, real'(current_y2)/16777216.0,  real'(tmp1_shift)/16777216.0);

        //  $display("weights[0][1] = %f, tanh[y1] = %f, y1[om] = %f, m01 = %f\n", real'(weights[0][1])/16777216.0, real'(tanh_y1_reg)/16777216.0, real'(current_y1)/16777216.0,  real'(m01_shift)/16777216.0);

        //  $display("weights[0][2] = %f, sin[y2] = %f, y2[om] = %f, m02 = %f\n", real'(weights[0][2])/16777216.0, real'(sin_y2_reg)/16777216.0, real'(current_y2)/16777216.0,  real'(m02_shift)/16777216.0);

        //  $display("weights[0][3] = %f, sin[y3] = %f, y3[om] = %f, m03 = %f\n", real'(weights[0][3])/16777216.0, real'(sin_y3_reg)/16777216.0, real'(current_y3)/16777216.0,  real'(m03_shift)/16777216.0);
        //  $display("weights[2][0] = %f, tanh[y0] = %f, y0[om] = %f, m20 = %f\n", real'(weights[2][0])/16777216.0, real'(tanh_y0_reg)/16777216.0, real'(current_y0)/16777216.0,  real'(m20_shift)/16777216.0);

        G1r0 <= 32'sd16777216 - tmp1_shift;  //40
        G2r0 <= a2 - tmp2_shift; //40

        state <= INIT_GSINGTANH; 
       end

       INIT_GSINGTANH: begin
            G1_tmp <= (G1r0) * (tanh_y4_reg);
            G2_tmp <= (G2r0) * (tanh_y3_reg);
            state <= INIT_GSINGTANH_SHIFT;
       end

        INIT_GSINGTANH_SHIFT: begin
            G1tanh <= (G1_tmp ) >>> 24;
            G2sin  <= (G2_tmp ) >>> 24;
            state <= INIT_PIPE_SUM;

        end


       INIT_PIPE_SUM: begin

        // $display("INIT_PIPE_SUM: y1sum=%f = -y1[0](%f) + m10(%f) + m12(%f) + m14(%f)",
        //     real'(-y1[0] + m10_shift + m12_shift + m14_shift)/16777216.0,
        //     real'(y1[0])/16777216.0,
        //     real'(m10_shift)/16777216.0,
        //     real'(m12_shift)/16777216.0,
        //     real'(m14_shift)/16777216.0);
            
            y0_sum[0] <= -y0[0] + m01_shift + m02_shift + m03_shift; // 40
            y1_sum[0] <= -y1[0] + m10_shift + m12_shift + m14_shift + f1;
            y2_sum[0] <= -y2[0] + m20_shift + m21_shift + m22_shift;
            y3_sum[0] <= -y3[0] + m30_shift + G2sin + f3; 
            y4_sum[0] <= -y4[0] + m41_shift + G1tanh; //32, 40, 48

            om <= 1;
            state <= INIT_OM;
       end
//--------------for(om=1;om<T+1;om++)------------------------------

        INIT_OM: begin
            // $display("INIT_OM: om=%0d r=%0d", om, r);
            // $display("y0[0] = %f, current_y0 = %f, m01 = %f, m02 = %f, m03 = %f, y0_sum[0] = %f\n", real'(y0[0])/16777216.0, real'(current_y0)/16777216.0, real'(m01_shift)/16777216.0, real'(m02_shift)/16777216.0,  real'(m03_shift)/16777216.0, real'(y0_sum[0])/16777216.0);
            // $display("y1[0] = %f, current_y1 = %f, m10 = %f, m12 = %f, f1 = %f, y1_sum[0] = %f\n", real'(y1[0])/16777216.0, real'(current_y1)/16777216.0, real'(m10_shift)/16777216.0, real'(m12_shift)/16777216.0,  real'(f1)/16777216.0, real'(y1_sum[0])/16777216.0);
            // $display("y2[0] = %f, current_y2 = %f, m20 = %f, m21 = %f, m22 = %f, y2_sum[0] = %f\n", real'(y2[0])/16777216.0, real'(current_y2)/16777216.0, real'(m20_shift)/16777216.0, real'(m21_shift)/16777216.0,  real'(m22_shift)/16777216.0, real'(y2_sum[0])/16777216.0);
            // $display("y3[0] = %f, current_y3 = %f, m30 = %f, G2sin = %f, f3 = %f, y3_sum[0] = %f\n", real'(y3[0])/16777216.0, real'(current_y3)/16777216.0, real'(m30_shift)/16777216.0, real'(G2sin)/16777216.0,  real'(f3)/16777216.0, real'(y3_sum[0])/16777216.0);
            // $display("y4[0] = %f, current_y4 = %f, m41 = %f, G1tanh = %f, y4_sum[0] = %f\n", real'(y4[0])/16777216.0, real'(current_y4)/16777216.0, real'(m41_shift)/16777216.0, real'(G1tanh)/16777216.0, real'(y4_sum[0])/16777216.0);


            acc0 <= 0; //w kazdej iteracji om na poczatku daje 0
            acc1 <= 0;
            acc2 <= 0;
            acc3 <= 0;
            acc4 <= 0;

            r <= 1;
            state <= MUL_ACC;//LOOP_R;
        end
        MUL_ACC: begin 
            mul_0 <= (y0_sum[r-1]) * (bg_lut[(om - r)]); //48 + 32 = 80
            mul_1 <= (y1_sum[r-1]) * (bg_lut[(om - r)]);
            mul_2 <= (y2_sum[r-1]) * (bg_lut[(om - r)]);
            mul_3 <= (y3_sum[r-1]) * (bg_lut[(om - r)]);
            mul_4 <= (y4_sum[r-1]) * (bg_lut[(om - r)]);

            state <= SHIIFT;
        end

        SHIIFT: begin
            
            // $display("y0_sum[%0d] = %f, om = %0d, bg_lut[%0d] = %f, mul_0 = %f\n", r-1, real'(y0_sum[r-1])/16777216.0,  om, (om-r), real'(bg_lut[(om-r)])/16777216.0,  real'(mul_0)/281474976710656.0);
            // $display("y1_sum[%0d] = %f, om = %0d, bg_lut[%0d] = %f, mul_1 = %f\n", r-1, real'(y1_sum[r-1])/16777216.0,  om, (om-r), real'(bg_lut[(om-r)])/16777216.0,  real'(mul_1)/281474976710656.0);
            // $display("y2_sum[%0d] = %f, om = %0d, bg_lut[%0d] = %f, mul_2 = %f\n", r-1, real'(y2_sum[r-1])/16777216.0,  om, (om-r), real'(bg_lut[(om-r)])/16777216.0,  real'(mul_2)/281474976710656.0);
            // $display("y3_sum[%0d] = %f, om = %0d, bg_lut[%0d] = %f, mul_3 = %f\n", r-1, real'(y3_sum[r-1])/16777216.0,  om, (om-r), real'(bg_lut[(om-r)])/16777216.0,  real'(mul_3)/281474976710656.0);
            // $display("y4_sum[%0d] = %f, om = %0d, bg_lut[%0d] = %f, mul_4 = %f\n", r-1, real'(y4_sum[r-1])/16777216.0,  om, (om-r), real'(bg_lut[(om-r)])/16777216.0,  real'(mul_4)/281474976710656.0);


            scaled_0 <= (mul_0 ) >>> 24; //80 - 24 -> 56
            scaled_1 <= (mul_1 ) >>> 24;
            scaled_2 <= (mul_2 ) >>> 24;
            scaled_3 <= (mul_3 ) >>> 24;
            scaled_4 <= (mul_4 ) >>> 24;

            state <= LOOP_R;
        end


//--------------for(r=1;r<om+1;om++)------------------------------
        LOOP_R: 
        begin

            // $display("LOOP_R om=%0d r=%0d scaled_0=%f acc0_before=%f acc0_after=%f",
            //     om, r,
            //     real'(scaled_0)/16777216.0,
            //     real'(acc0)/262144.0,
            //     real'(acc0 + scaled_0)/262144.0);

            acc0 <= acc0 + scaled_0;  //65 -> 66
            acc1 <= acc1 + scaled_1; 
            acc2 <= acc2 + scaled_2; 
            acc3 <= acc3 + scaled_3;
            acc4 <= acc4 + scaled_4; 

            if (r == om) begin
                state <= FINALIZE;
            end else begin
                r <= r + 1;
                state <= MUL_ACC; 
            end           
        end

        FINALIZE: 
        begin
            // $display("FINALIZE START: om=%0d", om);
            // $display("HDL y0[%0d] =%f, y1[%0d] = %f, y2[%0d] = %f, y3[%0d] = %f, y4[%0d] = %f", om, 
            //     real' (acc0 + y0[0]) /16777216.0, om,real' (acc1 + y1[0]) /16777216.0, om, real' (acc2+ y2[0]) /16777216.0, om, (acc3 + y3[0]) /16777216.0, om, (acc4 + y4[0]) /16777216.0 );
            // $display("HDL current_y0 =%f, current_y1 = %f, current_y2 = %f, current_y3 = %f, current_y4 = %f", om, 
            //     real' (current_y0) /16777216.0, om,real' (current_y1) /16777216.0, om, real' (current_y2) /16777216.0, om, (current_y3) /16777216.0, om, (current_y4) /16777216.0 );

            y0[om] <= acc0   + y0[0];
            y1[om] <= acc1   + y1[0];
            y2[om] <= acc2   + y2[0];
            y3[om] <= acc3   + y3[0];
            y4[om] <= acc4   + y4[0];

            state <= OM_START; //SEND;
        end
        OM_START: 
        begin
            
            start_pipe <= 0; //1;
            neuron_num <= 0; 

            state <= OM_WAIT_TO_SEND;
        end

        OM_WAIT_TO_SEND: begin

            state<= OM_START2;
        end

    OM_START2: 
        begin

            start_pipe <= 1;
            wait_cnt <= 0;
            state <= OM_WAIT_ONE;
        end

        OM_WAIT_ONE: begin
            start_pipe <= 0;
            wait_cnt <= wait_cnt +1;
            if(wait_cnt == SIN_LATENCY -1)begin  //-2
                state <= OM_LATCH;
            end
        end

        OM_LATCH: begin

        case (neuron_num)
            0: begin tanh_y0_reg<=tanh_out; sin_y0_reg<=sin_out; end
            1: begin tanh_y1_reg<=tanh_out; sin_y1_reg<=sin_out; end
            2: begin tanh_y2_reg<=tanh_out; sin_y2_reg<=sin_out; end
            3: begin tanh_y3_reg<=tanh_out; sin_y3_reg<=sin_out; end
            4: begin tanh_y4_reg<=tanh_out; sin_y4_reg<=sin_out; end
        endcase
        
        if (neuron_num == 4) begin
            neuron_num <= 0;
            state <= OM_MUL1;  
        end else begin
            neuron_num <= neuron_num + 1;
            state <= OM_START2;
        end
    end

    //-----------------------------------------------------------

        OM_MUL1: begin

            // $display("OM_MUL1 om=%0d: y1[om]=%f (expected -1.115 for om=1)",
            // om, real'(y1[om])/16777216.0);  

            //$display("HDL current_y0 =%f, current_y1 = %f, current_y2 = %f, current_y3 = %f, current_y4 = %f", om, 
                //real' (current_y0) /16777216.0, om,real' (current_y1) /16777216.0, om, real' (current_y2) /16777216.0, om, (current_y3) /16777216.0, om, (current_y4) /16777216.0 );

            // $display("HDL tanh(y0[%0d)] =%f, tanh(y1[%0d]) = %f, tanh(y2[%0d]) = %f, tanh(y3[%0d]) = %f, tanh(y4[%0d]) = %f", om, 
            //     real' (tanh_y0_reg) /16777216.0, om,real' (tanh_y1_reg) /16777216.0, om, real' (tanh_y2_reg) /16777216.0, om, (tanh_y3_reg) /16777216.0, om, (tanh_y4_reg) /16777216.0 );

            tmp1 <= (a1) * (tanh_y2_reg);
            tmp2 <= (a3) * (sin_y4_reg);

            m01 <= (weights[0][1]) * (tanh_y1_reg);
            m02 <= (weights[0][2]) * (sin_y2_reg);
            m03 <= (weights[0][3] * sin_y3_reg);

            m10 <= (weights[1][0]) * (sin_y0_reg);
            m12 <= (weights[1][2]) * (sin_y2_reg);
            m14 <= (weights[1][4]) * (sin_y4_reg);

            m20 <= (weights[2][0]) * (tanh_y0_reg); 
            m21 <= (weights[2][1]) * (tanh_y1_reg);
            m22 <=  (weights[2][2]) * (sin_y2_reg);

            m30 <= (weights[3][0]) * (tanh_y0_reg);

            m41 <= (weights[4][1]) * (tanh_y1_reg);

            state <= OM_MUL2;
       end

        OM_MUL2: begin

            tmp1_shift <= (tmp1 ) >>> 24;
            tmp2_shift <= (tmp2 ) >>> 24;

            m01_shift <= (m01 ) >>> 24;  //40 -> Q16.24
            m02_shift <= (m02 ) >>> 24; 
            m03_shift <= (m03 ) >>> 24;

            m10_shift <= (m10 ) >>> 24; 
            m12_shift <= (m12 ) >>> 24; 
            m14_shift <= (m14 ) >>> 24; 

            m20_shift <= (m20 ) >>> 24; 
            m21_shift <= (m21 ) >>> 24;
            m22_shift <=  (m22 ) >>> 24;

            m30_shift <= (m30 ) >>> 24;

            m41_shift <= (m41 ) >>> 24;

            state<= OM_G1G2;
        end



        OM_G1G2: begin
            G1r0 <= 32'sd16777216 - tmp1_shift;  //36
            G2r0 <= a2 - tmp2_shift; 
            state <= OM_GSINGTANH;
        end

        OM_GSINGTANH: begin

            G1_tmp <= (G1r0) * (tanh_y4_reg);
            G2_tmp <= (G2r0) * (tanh_y3_reg);

            state <= OM_GSINGTANH_SHIFT;
        end

        OM_GSINGTANH_SHIFT: begin
            G1tanh <= (G1_tmp ) >>> 24;
            G2sin  <= (G2_tmp ) >>> 24;
            
            state <= OM_SUM;
        end

            OM_SUM: begin

            y0_sum[om] <= -y0[om] + m01_shift + m02_shift + m03_shift; 
            y1_sum[om] <= -y1[om] + m10_shift+ m12_shift + m14_shift + f1;
            y2_sum[om] <= -y2[om] + m20_shift + m21_shift + m22_shift;
            y3_sum[om] <= -y3[om] + m30_shift + G2sin + f3; 
            y4_sum[om] <= -y4[om] + m41_shift + G1tanh; 

            //om <= 1;
            state <= SEND;
       end

        SEND: begin
            sample_out.y0 <= y0[om];
            sample_out.y1 <= y1[om];
            sample_out.y2 <= y2[om];
            sample_out.y3 <= y3[om];
            sample_out.y4 <= y4[om];
            sample_out.dt <= 0;

            sample_send <= 1;
            
            //if(om==T)state <= WAIT;
            if(om==T)state <= STOP;
            else begin 
                om <= om+1;
                state <= INIT_OM; //znowu iteracja po om albo kuniec
            end
        end
        STOP: begin
                //$display("AAAAAAA");

        end

        endcase
        
    end
end
//------------------------------------------------



endmodule
