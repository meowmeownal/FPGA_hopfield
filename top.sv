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
    .sample_send(sample_send),
    .sample_out(sample_out)    
);


//================ FIFO =================
DATA fifo_rd_data; 
logic f_empty, f_full;
logic f_wr_en, f_rd_en;

DATA f_wr_data;

// zapis do FIFO
always_ff @(posedge CLK100MHZ) begin
    if (rst) begin
        f_wr_en   <= 0;
        f_wr_data <= '0;
    end else begin
        f_wr_en <= 0; // default

        if (sample_send && !f_full) begin
            f_wr_en   <= 1;
            f_wr_data <= sample_out;
        end
    end
end

fifo fifo(
    .clk(CLK100MHZ),
    .rst(rst),
    .wr_en(f_wr_en),
    .wr_data(f_wr_data),
    .rd_en(f_rd_en),
    .rd_data(fifo_rd_data), 
    .full(f_full),
    .empty(f_empty)
);

//================ UART =================
logic [7:0] u_data;
logic u_start, u_busy;

uart_tx #(
    .CLK_HZ(100_000_000),   
    .BAUD(115200)
) uart (
    .clk(CLK100MHZ),
    .nrst(~rst),
    .tx_data(u_data),
    .tx_start(u_start),
    .tx_busy(u_busy),
    .txd(tx)
);

typedef enum logic [2:0] {
    IDLE,
    READ_FIFO, WAIT_DATA,
    SEND_BYTE,
    WAIT_START,
    WAIT_DONE
    //SEND_HEADER, WAIT_HDR_START, WAIT_HDR_DONE
    // SEND_H1, SEND_H2,
    // WAIT_H1, WAIT_H2,
    // WAIT_H2_DONE, WAIT_H1_DONE,
    // SEND_L1, SEND_L2,
    // WAIT_L1, WAIT_L2,
    // WAIT_L1_DONE, WAIT_L2_DONE
} state_t;

state_t state;

//logic [31:0] data_32;
DATA from_fifo_data;           
logic [4:0] byte_idx;           
// logic [7:0] current_byte
logic [191:0] data_flat; // 6*32 bits
assign data_flat = from_fifo_data;

logic [7:0] byte_hold [0:23];
genvar i;
generate
    for (i = 0; i < 24; i++) begin //24 bytes, per 8 bits
        assign byte_hold[i] = data_flat[191 - i*8 -: 8]; //-: 8 znaczy, ze lecimy w doł o 8 bitow
    end
endgenerate

always_ff @(posedge CLK100MHZ) begin
    if (rst) begin
        state   <= IDLE;
        f_rd_en <= 0;
        u_start <= 0;
        u_data  <= 0;
        //data_32 <= 0;
        byte_idx <= 0;
        from_fifo_data <= '0;
    end else begin
        f_rd_en <= 0;
        u_start <= 0;

        case (state)
        IDLE: begin
            if (!f_empty && !u_busy) begin
                f_rd_en <= 1;       
                state   <= READ_FIFO;
            end
        end

        READ_FIFO: begin
            state   <= WAIT_DATA;
        end

        WAIT_DATA: begin
            //data_32 <= fifo_rd_data.y0;
            from_fifo_data <= fifo_rd_data;
            byte_idx <= 0;
            state   <= SEND_BYTE;
        end

        // SEND_HEADER: begin
        //     u_data <= 8'hAA;
        //     u_start <= 1;
        //     state <= WAIT_HDR_START;
        // end
        // WAIT_HDR_START: begin
        //     if(u_busy)
        //         state<= WAIT_HDR_DONE;
        // end

        // WAIT_HDR_DONE: begin
        //     if(!u_busy)
        //         state <= SEND_BYTE;
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

        // SEND_H1: begin
        //     u_data  <= data_32[31:24]; 
        //     u_start <= 1;
            
        //     state   <= WAIT_H1;
        // end

        // WAIT_H1: begin
        //     if (u_busy)
        //         state <= WAIT_H1_DONE;
        // end
        // WAIT_H1_DONE: begin
        //     if(!u_busy)
        //         state<=SEND_H2;
        // end

        // SEND_H2: begin
        //     u_data <= data_32[23:16];
        //     u_start <= 1;
        //     state <= WAIT_H2;
        // end

        // WAIT_H2: begin
        //     if(u_busy)
        //         state <= WAIT_H2_DONE;
        // end
        // WAIT_H2_DONE: begin
        //     if(!u_busy)
        //         state <= SEND_L1;
        // end

        // SEND_L1: begin
        //     u_data  <= data_32[15:8];
        //     u_start <= 1;
        //     state   <= WAIT_L1;
        // end

        // WAIT_L1: begin
        //     if (u_busy)
        //         state <= WAIT_L1_DONE;
        // end

        // WAIT_L1_DONE: begin
        //     if(!u_busy)
        //         state <= SEND_L2;
        // end

        // SEND_L2: begin
        //     u_data <= data_32[7:0];
        //     u_start <= 1;
        //     state <= WAIT_L2;
        // end

        // WAIT_L2: begin
        //     if (u_busy)
        //         state <= WAIT_L2_DONE;
        // end
        // WAIT_L2_DONE: begin
        //     if(!u_busy)
        //         state <= IDLE;
        // end

        endcase
    end
end

endmodule
