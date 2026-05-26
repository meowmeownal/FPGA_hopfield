`timescale 1ns / 1ps

import types_pkg::*;

module top (
    input  logic CLK100MHZ,
    input  logic rst_btn, //_btn,
    input  logic start, 
    output logic tx,

    inout  wire SDA,
    inout  wire SCL
);

//================ NEURAL CORE =================
DATA sample_out;
(* mark_debug = "true" *) logic sample_send;
(* mark_debug = "true" *) logic uart_busy_neur_core;
//(* mark_debug = "true" *) 


logic rst; 
logic [1:0] rst_ff;
always_ff @(posedge CLK100MHZ) begin
    rst_ff[0] <= ~rst_btn;  //wysoi sttan
    rst_ff[1] <= rst_ff[0];
end
assign rst = rst_ff[1];


neural_core neur_calc(
    .clk(CLK100MHZ),
    .rst(rst),
    .start(start),
    .pause(uart_busy_neur_core), //f_full
    .sample_send(sample_send),
    .sample_out(sample_out)    
);


//================ FIFO =================
// DATA fifo_rd_data; 
// logic f_empty, f_full;
// logic f_wr_en, f_rd_en;

// DATA f_wr_data;

// // zapis do FIFO
// always_ff @(posedge CLK100MHZ) begin
//     if (rst) begin
//         f_wr_en   <= 0;
//         f_wr_data <= '0;
//     end else begin
//         f_wr_en <= 0; // default

//         if (sample_send && !f_full) begin
//             f_wr_en   <= 1;
//             f_wr_data <= sample_out;
//         end
//     end
// end

// fifo fifo(
//     .clk(CLK100MHZ),
//     .rst(rst),
//     .wr_en(f_wr_en),
//     .wr_data(f_wr_data),
//     .rd_en(f_rd_en),
//     .rd_data(fifo_rd_data), 
//     .full(f_full),
//     .empty(f_empty)
// );

//================ UART =================
logic [7:0] u_data;
logic u_start, u_busy;

uart_tx #(
    .CLK_HZ(100_000_000),   
    .BAUD(921600)
) uart (
    .clk(CLK100MHZ),
    .nrst(~rst),
    .tx_data(u_data),
    .tx_start(u_start),
    .tx_busy(u_busy),
    .txd(tx)
);
//========================================

typedef enum logic [2:0] {
    IDLE,
    //READ_FIFO, 
    WAIT_DATA,
    SEND_BYTE,
    WAIT_START,
    WAIT_DONE
} state_t;

(* mark_debug = "true" *) state_t state;

DATA from_neur_core_data; //from_fifo_data;           
logic [4:0] byte_idx;           
logic [191:0] data_flat; // 6*32 bits
assign data_flat = from_neur_core_data; //from_fifo_data;

logic [7:0] byte_hold [0:27];
assign byte_hold[0] = 8'hDE;
assign byte_hold[1] = 8'hAD;
assign byte_hold[2] = 8'hBE;
assign byte_hold[3] = 8'hEF;
genvar i;
generate
    for (i = 0; i < 24; i++) begin //24 bytes, per 8 bits
        assign byte_hold[i+4] = data_flat[191 - i*8 -: 8]; //-: 8 znaczy, ze lecimy w doł o 8 bitow
    end
endgenerate

assign uart_busy_neur_core = (state != IDLE) || sample_send;; // when state == idle -> urat = 0, is not busy

always_ff @(posedge CLK100MHZ) begin
    if (rst) begin
        state   <= IDLE;
        //f_rd_en <= 0;
        u_start <= 0;
        u_data  <= 0;
        byte_idx <= 0;
        from_neur_core_data <= '0;
    end else begin
        //f_rd_en <= 0;
        u_start <= 0;

        case (state)
        IDLE: begin
            // if (!f_empty && !u_busy) begin
            //     f_rd_en <= 1;       
            //     state   <= READ_FIFO;
            // end
            if(sample_send) begin
                from_neur_core_data <= sample_out;
                byte_idx <= 0;
                state <= WAIT_DATA;
            end
        end
        WAIT_DATA: begin
            state <= SEND_BYTE;
        end

        // READ_FIFO: begin
        //     state   <= WAIT_DATA;
        // end

        // WAIT_DATA: begin
        //     //data_32 <= fifo_rd_data.y0;
        //     from_neur_core_data <= fifo_rd_data;
        //     byte_idx <= 0;
        //     state   <= SEND_BYTE;
        // end

        SEND_BYTE: begin
            //u_data <= data_flat[191 - byte_idx*8]
            u_data <= byte_hold[byte_idx];
            u_start <= 1;
            state <= WAIT_START;

        end

        WAIT_START: begin
            if(u_busy) 
                state <= WAIT_DONE;

        end

        WAIT_DONE: begin
            if(!u_busy) begin
                if(byte_idx == 27)begin //24 bajty (all 5 neurons + time)
                    state <= IDLE;
                    byte_idx <= 0;
                end else begin
                    byte_idx <= byte_idx +1;
                    state <= SEND_BYTE;
                end
            end
        end

        endcase
    end
end



logic [7:0] data_received;
//from_neur_core_data.y1
logic signed [11:0] sample_q6_6_dac1;
logic signed [11:0] sample_q6_6_dac2;
logic signed [31:0] sample_delayed;

logic [11:0] dac1_data;
logic [15:0] data_send_dac1;

logic [11:0] dac2_data;
logic [15:0] data_send_dac2;


logic [7:0] current_addr;
logic [23:0] current_data;

logic start_i2c;
logic i2c_busy;

typedef enum logic [2:0] {

    DAC_IDLE,
    DAC_SEND_1,
    DAC_WAIT_1,
    DAC_WAIT_1_DONE,
    DAC_SEND_2,
    DAC_WAIT_2,
    DAC_WAIT_2_DONE

} dac_state_t;

dac_state_t dac_state;

always_ff @(posedge CLK100MHZ) begin

    if(rst)
        sample_delayed <= 0;
    else if(sample_send)
        sample_delayed <= from_neur_core_data.y1;

end

always_comb begin
    sample_q6_6_dac1 = from_neur_core_data.y1 >>> 20; //removing 20 last bits
    dac1_data = sample_q6_6_dac1 + 12'sd2048;

    data_send_dac1  = {4'b0000, dac1_data};


end

always_comb begin
    sample_q6_6_dac2 = sample_delayed >>> 20; //removing 20 last bits
    dac2_data = sample_q6_6_dac2 + 12'd2048;
    data_send_dac2  = {4'b0000, dac2_data};



end

always_ff @(posedge CLK100MHZ) begin
    if(rst) begin 
        dac_state <= DAC_IDLE;
        start_i2c <= 0;
        current_data<=0;
        current_addr<=0;

    end else begin
        start_i2c <= 0;
        case(dac_state)
        DAC_IDLE: begin
            if(sample_send) dac_state <= DAC_SEND_1;
        end
        DAC_SEND_1: begin
            if(!i2c_busy) begin
                current_addr <= 8'hC0;
                current_data <= {data_send_dac1, 8'b0};
                start_i2c <= 1;
                dac_state <= DAC_WAIT_1;
            end
        end
        DAC_WAIT_1: begin
            if(i2c_busy) dac_state <= DAC_WAIT_1_DONE;
        end

        DAC_WAIT_1_DONE: begin
            if(!i2c_busy) dac_state <= DAC_SEND_2;
        end

        DAC_SEND_2: begin
            if(!i2c_busy)begin
                current_addr <= 8'hC2;
                current_data <= data_send_dac2;
                start_i2c <= 1;
                dac_state <= DAC_WAIT_2;
            end
        end

        DAC_WAIT_2: begin
            if(i2c_busy)dac_state <= DAC_WAIT_2_DONE;
        end

        DAC_WAIT_2_DONE: begin 
            if(!i2c_busy)dac_state <= DAC_IDLE;
        end
    endcase
    end
end


i2c_master i2c_inst (

    .clk(CLK100MHZ),
    .rst(rst),
    .start(start_i2c),
    .dac_addr(current_addr),
    .data_send(current_data),
    .bytes_send(2),
    .bytes_receive(0), // so data_received is not used 
    .SDA(SDA),
    .SCL(SCL),
    .i2c_busy(i2c_busy),
    .data_received(data_received)

);


endmodule
