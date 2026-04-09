`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04.04.2026 19:48:33
// Design Name: 
// Module Name: hopfield_dyn
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



import types_pkg::*;

module neural_core #(
    parameter T = 20 //mozna bedzie zwiekszyc :))
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


 
    //6 bitow całkowitych, 18 ulamkowych -> Q6.18 
    typedef logic signed [23:0] q6_18_t; //w tej kolejnosic to jest ilosc bitów!!

    q6_18_t bg_lut [0:T];
    initial begin
        $readmemh("bg_lut.mem", bg_lut);
    end
    //---------------------------------------------------------------------------

    // pamięć (BRAM)
    q6_18_t y0     [0:T];
    q6_18_t y1     [0:T];
    q6_18_t y2     [0:T];
    q6_18_t y3     [0:T];
    q6_18_t y4     [0:T];

    q6_18_t y0_sum [0:T];
    q6_18_t y1_sum [0:T];
    q6_18_t y2_sum [0:T];
    q6_18_t y3_sum [0:T];
    q6_18_t y4_sum [0:T];

initial begin
    y0[0] =  24'sd209715;
    y1[0] = 24'sd78643;
    y2[0] = 24'sd104858;
    y3[0] = 24'sd157286;
    y4[0] = 24'sd183501; 
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


//---------------WEIGHTS MATRIX----------------------------------
q6_18_t weights [0:N-1][0:N-1];
initial begin
    weights[0][0] = 24'sd0;
    weights[0][1] = -24'sd78643;   // -0.3 * 2^18
    weights[0][2] = -24'sd209715;  // -0.8
    weights[0][3] = -24'sd157286;  // -0.6
    weights[0][4] = 24'sd0;

    weights[1][0] = -24'sd786432;  // -3.0
    weights[1][1] = 24'sd0;
    weights[1][2] = 24'sd524288;   // 2.0
    weights[1][3] = 24'sd0;
    weights[1][4] = 24'sd104858;   // 0.4

    
    weights[2][0] = 24'sd445645; //1.7
    weights[2][1] = -24'sd104858;
    weights[2][2] = 24'sd786432;
    weights[2][3] = 24'sd0;
    weights[2][4] = 24'sd0;

    
    weights[3][0] = 24'sd183501; //0.7
    weights[3][1] = 24'sd0;
    weights[3][2] = 24'sd0;   // 2.0
    weights[3][3] = 24'sd0;
    weights[3][4] = 24'sd104858; 

    
    weights[4][0] = 24'sd0;  // -3.0
    weights[4][1] = 24'sd445645; //1.7
    weights[4][2] = 24'sd0;   // 2.0
    weights[4][3] = 24'sd0;
    weights[4][4] = 24'sd0; 

end
//---------------------------------------

typedef enum logic [3:0] {
    WAIT, //stan bezczynnosci, czekanie na start
    INIT, //wartosc poczatkow neuronu
    INIT_OM, //poczatkowa iteracja om
    WAIT_PIPE,
    INIT_PIPE_MUL, //mnozenia, pierdzenia
    INIT_PIPE_SUM,
    LOOP_R, //iteracja r
    FINALIZE,
    OM_START,
    OM_WAIT,
    OM_SUM,
    OM_MUL,
    SEND, //wysylanie do fifo
    STOP
} state_t;

state_t state; //zmienna state_t, ktora bbedzize mowila, co kod teraz robi

logic [12:0] om;
logic [12:0] r;

logic signed [47:0] acc0, acc1, acc2, acc3, acc4; //do przechowywania w danej chwili wartosci neuronow

q6_18_t tanh_y0_om, tanh_y1_om, tanh_y2_om, tanh_y3_om, tanh_y4_om;
q6_18_t sin_y0_om,  sin_y1_om,  sin_y2_om,  sin_y3_om,  sin_y4_om;

q6_18_t tanh_y0_reg, tanh_y1_reg, tanh_y2_reg, tanh_y3_reg, tanh_y4_reg;
q6_18_t sin_y0_reg,  sin_y1_reg,  sin_y2_reg,  sin_y3_reg,  sin_y4_reg;

logic valid_tanh0, valid_tanh1, valid_tanh2, valid_tanh3, valid_tanh4;
logic valid_sin0,  valid_sin1,  valid_sin2,  valid_sin3,  valid_sin4;

logic valid_tanh0_reg, valid_tanh1_reg, valid_tanh2_reg, valid_tanh3_reg, valid_tanh4_reg;
logic valid_sin0_reg,  valid_sin1_reg,  valid_sin2_reg,  valid_sin3_reg,  valid_sin4_reg;

// q6_18_t tanh_y0_buf, tanh_y1_buf, tanh_y2_buf, tanh_y3_buf, tanh_y4_buf;
// q6_18_t sin_y0_buf,  sin_y1_buf,  sin_y2_buf,  sin_y3_buf,  sin_y4_buf;

//----------------OM pętla------------------------
fast_tanh th0 (
    .clk(clk), 
    .rst(rst), 
    .valid_in(start_pipe), 
    .x(current_y0), 
    .valid_out(valid_tanh0), 
    .y(tanh_y0_om)
    );
fast_tanh th1 (
    .clk(clk), 
    .rst(rst), 
    .valid_in(start_pipe), 
    .x(current_y1), 
    .valid_out(valid_tanh1), 
    .y(tanh_y1_om)
    );
fast_tanh th2 (
    .clk(clk), 
    .rst(rst), 
    .valid_in(start_pipe), 
    .x(current_y2), 
    .valid_out(valid_tanh2), 
    .y(tanh_y2_om)
    );
fast_tanh th3 (
    .clk(clk), 
    .rst(rst), 
    .valid_in(start_pipe), 
    .x(current_y3), 
    .valid_out(valid_tanh3), 
    .y(tanh_y3_om)
    );
fast_tanh th4 (
    .clk(clk), 
    .rst(rst), 
    .valid_in(start_pipe), 
    .x(current_y4), 
    .valid_out(valid_tanh4), 
    .y(tanh_y4_om)
    );

fast_sin s0 (
    .clk(clk), 
    .rst(rst), 
    .valid_in(start_pipe), 
    .x(current_y0), 
    .valid_out(valid_sin0), 
    .y(sin_y0_om)
    );

    // assign sin_y0_om = 24'sd0;
    // assign valid_sin0 = 1;
    
fast_sin s1 (
    .clk(clk), 
    .rst(rst), 
    .valid_in(start_pipe), 
    .x(current_y1), 
    .valid_out(valid_sin1), 
    .y(sin_y1_om)
    );
fast_sin s2 (
    .clk(clk), 
    .rst(rst), 
    .valid_in(start_pipe), 
    .x(current_y2), 
    .valid_out(valid_sin2), 
    .y(sin_y2_om)
    );
fast_sin s3 (
    .clk(clk), 
    .rst(rst), 
    .valid_in(start_pipe), 
    .x(current_y3), 
    .valid_out(valid_sin3), 
    .y(sin_y3_om)
    );
fast_sin s4 (
    .clk(clk), 
    .rst(rst), 
    .valid_in(start_pipe), 
    .x(current_y4), 
    .valid_out(valid_sin4), 
    .y(sin_y4_om)
    );
//-------------------------------------
q6_18_t m01, m02, m03;
q6_18_t m10, m12, m14;
q6_18_t m20, m21, m22;
q6_18_t m30;
q6_18_t m41;

q6_18_t f1 = 24'sd0;
q6_18_t f3 = 24'sd0;
q6_18_t a1 = -24'sd576717;
q6_18_t a2 = 24'sd859832;  //changing that
q6_18_t a3 = 24'sd314573;

q6_18_t tmp1, G1r0;
q6_18_t tmp2, G2r0;

q6_18_t current_y0;
q6_18_t current_y1;
q6_18_t current_y2;
q6_18_t current_y3;
q6_18_t current_y4;

always_comb begin
    current_y0 = 0;
    current_y1 = 0;
    current_y2 = 0;
    current_y3 = 0;
    current_y4 = 0;

    if (state inside {INIT, WAIT_PIPE, INIT_PIPE_MUL, INIT_PIPE_SUM})begin
        current_y0 = y0[0];
        current_y1 = y1[0];
        current_y2 = y2[0];
        current_y3 = y3[0];
        current_y4 = y4[0];

    end else if (state inside {OM_START, OM_WAIT, OM_MUL, OM_SUM}) begin
        current_y0 = y0[om];
        current_y1 = y1[om];
        current_y2 = y2[om];
        current_y3 = y3[om];
        current_y4 = y4[om];
    end
end

logic start_pipe;

localparam TANH_LATENCY = 25;  
localparam SIN_LATENCY  = 30;  
localparam MAX_LATENCY  = 40;//(TANH_LATENCY > SIN_LATENCY) ? TANH_LATENCY : SIN_LATENCY;

logic [5:0] wait_cnt; 

always_ff @(posedge clk) begin
    if (rst) begin
        state <= WAIT;
        om <= 1;
        r <= 1;
        sample_send <= 0;
        start_pipe <= 0;

        tmp1 <= 0; 
        tmp2 <= 0; 
        G1r0 <= 0;
        G2r0 <= 0;
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
        
        valid_tanh0_reg <= 0;
        valid_tanh1_reg <= 0;
        valid_tanh2_reg <= 0;
        valid_tanh3_reg <= 0;
        valid_tanh4_reg <= 0;

        valid_sin0_reg <= 0;
        valid_sin1_reg <= 0;
        valid_sin2_reg <= 0;
        valid_sin3_reg <= 0;
        valid_sin4_reg <= 0;

    end else begin
        //$display("t=%0t start_pipe=%b valid_tanh0=%b", $time, start_pipe, valid_tanh0);
        sample_send <=0;
        case (state)

        WAIT:
            if(start) state <=INIT;
        INIT: begin
            start_pipe <= 1;
            wait_cnt <= 0;

            valid_tanh0_reg <= 0;
            valid_tanh1_reg <= 0;
            valid_tanh2_reg <= 0;
            valid_tanh3_reg <= 0;
            valid_tanh4_reg <= 0;

            valid_sin0_reg <= 0;
            valid_sin1_reg <= 0;
            valid_sin2_reg <= 0;
            valid_sin3_reg <= 0;
            valid_sin4_reg <= 0;

            state<=WAIT_PIPE; //czekamy na wyniki
        end 
        WAIT_PIPE: begin

            // start_pipe <= 0;
            // if (valid_tanh0) begin
            //     $display("WAIT_PIPE: tanh0=%h at t=%0t", tanh_y0_om, $time);
            //     valid_tanh0_reg <= 1;
            //     tanh_y0_reg <= tanh_y0_om;
            // end
            // if (valid_tanh1) begin
            //     $display("WAIT_PIPE: tanh1=%h at t=%0t", tanh_y1_om, $time);
            //     valid_tanh1_reg <= 1;
            //     tanh_y1_reg <= tanh_y1_om;
            // end
            // if (valid_tanh2) begin
            //     $display("WAIT_PIPE: tanh2=%h at t=%0t", tanh_y2_om, $time);
            //     valid_tanh2_reg <= 1;
            //     tanh_y2_reg <= tanh_y2_om;
            // end
            // if (valid_tanh3) begin
            //     $display("WAIT_PIPE: tanh3=%h at t=%0t", tanh_y3_om, $time);
            //     valid_tanh3_reg <= 1;
            //     tanh_y3_reg <= tanh_y3_om;
            // end
            // if (valid_tanh4) begin
            //     $display("WAIT_PIPE: tanh4=%h at t=%0t", tanh_y4_om, $time);
            //     valid_tanh4_reg <= 1;
            //     tanh_y4_reg <= tanh_y4_om;
            // end
            
            // if (valid_sin0) begin
            //     $display("WAIT_PIPE: sin0=%h at t=%0t", sin_y0_om, $time);
            //     valid_sin0_reg <= 1;
            //     sin_y0_reg <= sin_y0_om;
            // end
            // if (valid_sin1) begin
            //     $display("WAIT_PIPE: sin1=%h at t=%0t", sin_y1_om, $time);
            //     valid_sin1_reg <= 1;
            //     sin_y1_reg <= sin_y1_om;
            // end
            // if (valid_sin2) begin
            //     $display("WAIT_PIPE: sin2=%h at t=%0t", sin_y2_om, $time);
            //     valid_sin2_reg <= 1;
            //     sin_y2_reg <= sin_y2_om;
            // end
            // if (valid_sin3) begin
            //     $display("WAIT_PIPE: sin3=%h at t=%0t", sin_y3_om, $time);
            //     valid_sin3_reg <= 1;
            //     sin_y3_reg <= sin_y3_om;
            // end
            // if (valid_sin4) begin
            //     $display("WAIT_PIPE: sin4=%h at t=%0t", sin_y4_om, $time);
            //     valid_sin4_reg <= 1;
            //     sin_y4_reg <= sin_y4_om;
            // end
            
            // if (valid_tanh0_reg && valid_tanh1_reg && valid_tanh2_reg &&
            //     valid_tanh3_reg && valid_tanh4_reg &&
            //     valid_sin0_reg  && valid_sin1_reg  && valid_sin2_reg &&
            //     valid_sin3_reg  && valid_sin4_reg) begin
                
            //     state <= INIT_PIPE_MUL;

            if (wait_cnt < MAX_LATENCY) begin
                wait_cnt <= wait_cnt +1;
                if(wait_cnt == 0) begin
                    start_pipe <= 0;
                end

            end else begin
            
                valid_tanh0_reg <= 1;
                tanh_y0_reg <= tanh_y0_om;

                valid_tanh1_reg <= 1;
                tanh_y1_reg <= tanh_y1_om;

                valid_tanh2_reg <= 1;
                tanh_y2_reg <= tanh_y2_om;

                valid_tanh3_reg <= 1;
                tanh_y3_reg <= tanh_y3_om;

                valid_tanh4_reg <= 1;
                tanh_y4_reg <= tanh_y4_om;

                valid_sin0_reg <= 1;
                sin_y0_reg <= sin_y0_om;

                valid_sin1_reg <= 1;
                sin_y1_reg <= sin_y1_om;

                valid_sin2_reg <= 1;
                sin_y2_reg <= sin_y2_om;

                valid_sin3_reg <= 1;
                sin_y3_reg <= sin_y3_om;

                valid_sin4_reg <= 1;
                sin_y4_reg <= sin_y4_om;


               state <= INIT_PIPE_MUL;
            end
                 
        end
        
        INIT_PIPE_MUL: begin

            tmp1 <= (a1 * tanh_y2_reg) >>> 18;
            tmp2 <= (a3 * sin_y4_reg) >>> 18;

            m01 <= (weights[0][1] * tanh_y1_reg) >>> 18;
            m02 <= (weights[0][2] * sin_y2_reg) >>> 18;
            m03 <= (weights[0][3] * sin_y3_reg)>>> 18;

            m10 <= (weights[1][0] * sin_y0_reg) >>> 18;
            m12 <= (weights[1][2] * sin_y2_reg) >>> 18;
            m14 <= (weights[1][4] * sin_y4_reg) >>> 18;

            m20 <= (weights[2][0] * tanh_y0_reg) >>> 18; 
            m21 <= (weights[2][1] * tanh_y1_reg) >>> 18;
            m22 <=  (weights[2][2] * sin_y2_reg) >>> 18;

            m30 <= (weights[3][0] * tanh_y0_reg) >>> 18;

            m41 <= (weights[4][1] * tanh_y1_reg) >>> 18;

            state <= INIT_PIPE_SUM;
            
            // end 
            
       end
       INIT_PIPE_SUM: begin

            G1r0 <= (tmp1* tanh_y4_reg) >>> 18;
            G2r0 <= (tmp2* tanh_y3_reg) >>> 18;
            
            y0_sum[0] <= -y0[0] + m01 + m02 + m03;
            y1_sum[0] <= -y1[0] + m10 + m12 + m14 + f1;
            y2_sum[0] <= -y2[0] + m20 + m21 + m22;
            y3_sum[0] <= -y3[0] + m30 + a2 - G2r0 + f3;
            y4_sum[0] <= -y4[0] + m41 +  24'sd262144 - G1r0;

            om <= 1;
            state <= INIT_OM;
       end
//--------------for(om=1;om<T+1;om++)------------------------------

        INIT_OM: begin
            acc0 <= 0; //w kazdej iteracji om na poczatku daje 0
            acc1 <= 0;
            acc2 <= 0;
            acc3 <= 0;
            acc4 <= 0;

            r <= 1;
            state <= LOOP_R;
        end
//--------------for(r=1;r<om+1;om++)------------------------------
        LOOP_R: begin
            acc0 <= acc0 + ((y0_sum[r-1] * bg_lut[T-(om - r)])>>> 20);
            acc1 <= acc1 + ((y1_sum[r-1] * bg_lut[T-(om - r)]))>>> 20;
            acc2 <= acc2 + ((y2_sum[r-1] * bg_lut[T-(om - r)]))>>> 20;
            acc3 <= acc3 + ((y3_sum[r-1] * bg_lut[T-(om - r)])>>> 20);
            acc4 <= acc4 + ((y4_sum[r-1] * bg_lut[T-(om - r)])>>> 20);

            $display("om=%0d r=%0d y0_sum=%h bg=%h acc0=%h",
            om, r, y0_sum[r-1], bg_lut[T-(om-r)], acc0);
            if (acc0 > 24'sd800000 || acc0 < -24'sd800000)
                $display("OVERFLOW acc0=%h", acc0);
                
            if (r == om) begin
                state <= FINALIZE;
            end else begin
                r <= r + 1;
                state <= LOOP_R; //tutah ogarnac, bo wsm zwiekszam r, ale czy y1_sum[r+1] istnieje?
            end
            
        end

        FINALIZE: begin
            y0[om] <= (acc0 ) + y0[0];
            y1[om] <= (acc1 ) + y1[0];
            y2[om] <= (acc2 ) + y2[0];
            y3[om] <= (acc3 ) + y3[0];
            y4[om] <= (acc4) + y4[0];

            state <= OM_START; //SEND;
        end
        OM_START: begin
            start_pipe <= 1;
            wait_cnt <= 0;

            valid_tanh0_reg <= 0;
            valid_tanh1_reg <= 0;
            valid_tanh2_reg <= 0;
            valid_tanh3_reg <= 0;
            valid_tanh4_reg <= 0;

            valid_sin0_reg <= 0;
            valid_sin1_reg <= 0;
            valid_sin2_reg <= 0;
            valid_sin3_reg <= 0;
            valid_sin4_reg <= 0;

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
            

            //pipe_cnt <= 0;
            state <= OM_WAIT;
        end
        OM_WAIT: begin

            // start_pipe <= 0;

            // if (valid_tanh0) begin
            //     $display("OM_WAIT: tanh0=%h at t=%0t", tanh_y0_om, $time);
            //     valid_tanh0_reg <= 1;
            //     tanh_y0_reg <= tanh_y0_om;
            // end
            // if (valid_tanh1) begin
            //     $display("OM_WAIT: tanh1=%h at t=%0t", tanh_y1_om, $time);
            //     valid_tanh1_reg <= 1;
            //     tanh_y1_reg <= tanh_y1_om;
            // end
            // if (valid_tanh2) begin
            //     $display("OM_WAIT: tanh2=%h at t=%0t", tanh_y2_om, $time);
            //     valid_tanh2_reg <= 1;
            //     tanh_y2_reg <= tanh_y2_om;
            // end
            // if (valid_tanh3) begin
            //     $display("OM_WAIT: tanh3=%h at t=%0t", tanh_y3_om, $time);
            //     valid_tanh3_reg <= 1;
            //     tanh_y3_reg <= tanh_y3_om;
            // end
            // if (valid_tanh4) begin
            //     $display("OM_WAIT: tanh4=%h at t=%0t", tanh_y4_om, $time);
            //     valid_tanh4_reg <= 1;
            //     tanh_y4_reg <= tanh_y4_om;
            // end
            
            // if (valid_sin0) begin
            //     $display("OM_WAIT: sin0=%h at t=%0t", sin_y0_om, $time);
            //     valid_sin0_reg <= 1;
            //     sin_y0_reg <= sin_y0_om;
            // end
            // if (valid_sin1) begin
            //     $display("OM_WAIT: sin1=%h at t=%0t", sin_y1_om, $time);
            //     valid_sin1_reg <= 1;
            //     sin_y1_reg <= sin_y1_om;
            // end
            // if (valid_sin2) begin
            //     $display("OM_WAIT: sin2=%h at t=%0t", sin_y2_om, $time);
            //     valid_sin2_reg <= 1;
            //     sin_y2_reg <= sin_y2_om;
            // end
            // if (valid_sin3) begin
            //     $display("OM_WAIT: sin3=%h at t=%0t", sin_y3_om, $time);
            //     valid_sin3_reg <= 1;
            //     sin_y3_reg <= sin_y3_om;
            // end
            // if (valid_sin4) begin
            //     $display("OM_WAIT: sin4=%h at t=%0t", sin_y4_om, $time);
            //     valid_sin4_reg <= 1;
            //     sin_y4_reg <= sin_y4_om;
            // end
            
            // if (valid_tanh0_reg && valid_tanh1_reg && valid_tanh2_reg &&
            //     valid_tanh3_reg && valid_tanh4_reg &&
            //     valid_sin0_reg  && valid_sin1_reg  && valid_sin2_reg &&
            //     valid_sin3_reg  && valid_sin4_reg) begin
                
            //     state <= OM_MUL;
            //-----------------------------------------------------------
 
            if (wait_cnt < MAX_LATENCY) begin
                wait_cnt <= wait_cnt +1;
                if(wait_cnt == 0) begin
                    start_pipe <= 0;
                end

            end else begin
            
                valid_tanh0_reg <= 1;
                tanh_y0_reg <= tanh_y0_om;

                valid_tanh1_reg <= 1;
                tanh_y1_reg <= tanh_y1_om;

                valid_tanh2_reg <= 1;
                tanh_y2_reg <= tanh_y2_om;

                valid_tanh3_reg <= 1;
                tanh_y3_reg <= tanh_y3_om;

                valid_tanh4_reg <= 1;
                tanh_y4_reg <= tanh_y4_om;

                valid_sin0_reg <= 1;
                sin_y0_reg <= sin_y0_om;

                valid_sin1_reg <= 1;
                sin_y1_reg <= sin_y1_om;

                valid_sin2_reg <= 1;
                sin_y2_reg <= sin_y2_om;

                valid_sin3_reg <= 1;
                sin_y3_reg <= sin_y3_om;

                valid_sin4_reg <= 1;
                sin_y4_reg <= sin_y4_om;

                state <= OM_MUL; 
   
            end
        end

        OM_MUL: begin

            tmp1 <= (a1 * tanh_y2_reg) >>> 18;
            tmp2 <= (a3 * sin_y4_reg) >>> 18;

            m01 <= (weights[0][1] * tanh_y1_reg) >>> 18;
            m02 <= (weights[0][2] * sin_y2_reg) >>> 18;
            m03 <= (weights[0][3] * sin_y3_reg)>>> 18;

            m10 <= (weights[1][0] * sin_y0_reg) >>> 18;
            m12 <= (weights[1][2] * sin_y2_reg) >>> 18;
            m14 <= (weights[1][4] * sin_y4_reg) >>> 18;

            m20 <= (weights[2][0] * tanh_y0_reg) >>> 18; 
            m21 <= (weights[2][1] * tanh_y1_reg) >>> 18;
            m22 <=  (weights[2][2] * sin_y2_reg) >>> 18;

            m30 <= (weights[3][0] * tanh_y0_reg) >>> 18;

            m41 <= (weights[4][1] * tanh_y1_reg) >>> 18;

            state <= OM_SUM;
       end

        OM_SUM: begin

            G1r0 <= (tmp1* tanh_y4_reg) >>> 18;
            G2r0 <= (tmp2* tanh_y3_reg) >>> 18;
            
            y0_sum[om] <= -y0[om] + m01 + m02 + m03;
            y1_sum[om] <= -y1[om] + m10 + m12 + m14 + f1;
            y2_sum[om] <= -y2[om] + m20 + m21 + m22;
            y3_sum[om] <= -y3[om] + m30 + a2 - G2r0 + f3;
            y4_sum[om] <= -y4[om] + m41 +  24'sd262144 - G1r0;

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
            if(om==T+1)state <= STOP;
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
