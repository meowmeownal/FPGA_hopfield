`timescale 1ns / 1ps

import types_pkg::*;

module top (
    input  logic CLK100MHZ,
    input  logic rst_btn, //_btn,
    input  logic start, 
    output logic tx
);

//================ NEURAL CORE =================
DATA sample_out;
logic sample_send;
logic uart_busy_neur_core;
//(* mark_debug = "true" *) 


logic rst; 
logic [1:0] rst_ff;
always_ff @(posedge CLK100MHZ) begin
    rst_ff[0] <= ~rst_btn;  //wysoi sttan
    rst_ff[1] <= rst_ff[0];
end

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

state_t state;

DATA from_neur_core_data; //from_fifo_data;           
logic [4:0] byte_idx;           
logic [191:0] data_flat; // 6*32 bits
assign data_flat = from_neur_core_data; //from_fifo_data;

logic [7:0] byte_hold [0:23];
genvar i;
generate
    for (i = 0; i < 24; i++) begin //24 bytes, per 8 bits
        assign byte_hold[i] = data_flat[191 - i*8 -: 8]; //-: 8 znaczy, ze lecimy w doł o 8 bitow
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
                if(byte_idx == 23)begin //24 bajty (all 5 neurons + time)
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

endmodule
