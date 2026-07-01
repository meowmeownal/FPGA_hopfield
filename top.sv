`timescale 1ns / 1ps

import types_pkg::*;

module top (
    input  logic CLK100MHZ,
    input  logic rst_btn, //_btn,
    input  logic start, 
    output logic tx,

    inout wire SDA,
    inout wire SCL
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
    .pause(uart_busy_neur_core), //uart_busy_neur_core), //f_full
    .sample_send(sample_send),
    .sample_out(sample_out)    
);


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

assign uart_busy_neur_core = (state != IDLE) || sample_send; // when state == idle -> urat = 0, is not busy

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
(* mark_debug = "true" *) logic signed [31:0] sample_delayed;
(* mark_debug = "true" *) logic [11:0] dac1_data;
logic [15:0] data_send_dac1;

logic [11:0] dac2_data;
logic [15:0] data_send_dac2;


(* mark_debug = "true" *) logic [7:0] current_addr;
(* mark_debug = "true" *) logic [15:0] current_data;

(* mark_debug = "true" *) logic start_i2c;
//(* mark_debug = "true" *) logic i2c_busy;

typedef enum logic [2:0] {

    DAC_IDLE,
    DAC_SEND_1,
    DAC_WAIT_1,
    DAC_WAIT_1_DONE,
    DAC_DELAY,
    DAC_SEND_2,
    DAC_WAIT_2,
    DAC_WAIT_2_DONE

} dac_state_t;

(* mark_debug = "true" *) dac_state_t dac_state;

always_ff @(posedge CLK100MHZ) begin

    if(rst)
        sample_delayed <= 0;
    else if(sample_send)
        sample_delayed <= sample_out.y0; //y(n-1)

end
(* mark_debug = "true" *) logic signed [31:0] dac1_hold;
logic signed [31:0] dac2_hold;

always_ff @(posedge CLK100MHZ) begin
    if(rst) begin
        dac1_hold <=0;
        dac2_hold <=0;
    end else if(sample_send) begin //when neural_core starts sending data
        dac1_hold <= sample_out.y0;
        dac2_hold <= sample_delayed;
    end
end

logic signed [63:0] shifted_dac1, shifted_dac2;
(* mark_debug = "true" *) logic signed [63:0] dac1_raw, dac2_raw;

logic signed [63:0] dac1_hold_hold, dac2_hold_hold;
//logic [15:0] buff1, buff2;

always_comb begin
    dac1_hold_hold = $signed(dac1_hold);
    shifted_dac1 = dac1_hold_hold + 64'sd140929229;
    dac1_raw = (shifted_dac1 * 64'sd975) >>> 26; //
    dac1_data = (dac1_raw > 4095) ? 12'd4095 : dac1_raw[11:0];
    data_send_dac1 = {4'b0100, dac1_data};

//-2.1, 2.1
    dac2_hold_hold = $signed(dac2_hold);
    shifted_dac2 = dac2_hold_hold + 64'sd140929229; //+2.1
    dac2_raw = (shifted_dac2 * 64'sd975) >>> 26; //4095/ 4.2
    dac2_data = (dac2_raw > 4095) ? 12'd4095 : dac2_raw[11:0];
    data_send_dac2 = {4'b0100, dac2_data}; 
end


logic dac_pending;

always_ff @(posedge CLK100MHZ) begin
    if(rst)
        dac_pending <= 0;
    else if(sample_send)
        dac_pending <= 1;        
    else if(dac_state == DAC_SEND_1)
        dac_pending <= 0;       
end

logic [15:0] delay_counter;
(* mark_debug = "true" *)  logic [15:0] current_data_dac1_hold;
logic [15:0] current_data_dac2_hold;

always_ff @(posedge CLK100MHZ) begin
    if(rst) begin
        current_data_dac1_hold <= 0;
        current_data_dac2_hold <= 0;
    end else if(sample_send) begin
        current_data_dac1_hold <= data_send_dac1;
        current_data_dac2_hold <= data_send_dac2;
    end
end

always_ff @(posedge CLK100MHZ) begin
    if(rst) begin 
        start_i2c <= 0;
        current_data<=0;
        current_addr<=0;
        delay_counter <= 0;
//       current_data_dac1_hold<=0;
//       current_data_dac2_hold<=0;
        
        dac_state <= DAC_IDLE;

    end else begin
        start_i2c <= 0;
        case(dac_state)

        DAC_IDLE: begin
            delay_counter <= 0;
            if(dac_pending && !i2c_busy) begin //&& !i2c_busy
//                current_data_dac1_hold<=data_send_dac1;
//                current_data_dac2_hold<=data_send_dac2;
                dac_state <= DAC_SEND_1;
           end
        end
        DAC_SEND_1: begin
                //$display("%t test_dac data=%h", $time, test_dac);
                current_addr <= 8'hC0;
                current_data <= 16'h0BB8; //current_data_dac1_hold; //data_send_dac1;//current_data_dac1_hold;//16'h0BB8; //
                start_i2c <= 1;
                dac_state <= DAC_WAIT_1;

        end
        DAC_WAIT_1: begin
            start_i2c <= 0;
            if(i2c_busy) begin
                dac_state <= DAC_WAIT_1_DONE;
////            end else begin
////                start_i2c <= 1;
            end
        end

        DAC_WAIT_1_DONE: begin
            if(!i2c_busy) 
                dac_state <= DAC_DELAY;
        end

        DAC_DELAY: begin
            if(delay_counter < 16'd100) begin
                delay_counter <= delay_counter + 1;
            end else begin
                delay_counter <= 0;
                dac_state <= DAC_SEND_2;
            end
        end 

        DAC_SEND_2: begin
                current_addr <= 8'hC2;
                current_data <= current_data_dac2_hold; //data_send_dac2;//current_data_dac2_hold; //16'h0BB8;//{8'b0, 4'b0100, dac1_data}; //0- 4095, 3.3V
                start_i2c <= 1;
                dac_state <= DAC_WAIT_2;

        end

        DAC_WAIT_2: begin
            start_i2c <= 0;
            if(i2c_busy)begin 
//                start_i2c <= 0;
                dac_state <= DAC_WAIT_2_DONE;
////            end else begin
////                start_i2c <= 1; 
            end
        end

        DAC_WAIT_2_DONE: begin 
            if(!i2c_busy) 
                dac_state <= DAC_IDLE;
        end
    endcase
    end
end

//primitive input/output buffer
wire SCL_in, SDA_in;
wire SCL_tx_top, SDA_tx_top;

`ifdef SYNTHESIS
    // IOBUF iobuf_scl (.O(SCL_in), .I(1'b0), .T(SCL_tx_top), .IO(SCL));
    // IOBUF iobuf_sda (.O(SDA_in), .I(1'b0), .T(SDA_tx_top), .IO(SDA));


    //https://docs.amd.com/r/en-US/ug974-vivado-ultrascale-libraries/IOBUF
    IOBUF IOBUF_scl (
   .O(SCL_in),   // 1-bit output: Buffer output
   .I(1'b0),   // 1-bit input: Buffer input
   .IO(SCL), // 1-bit inout: Buffer inout (connect directly to top-level port)
   .T(SCL_tx_top)    // 1-bit input: 3-state enable input
);
    IOBUF IOBUF_scl (
   .O(SDA_in),   // 1-bit output: Buffer output
   .I(1'b0),   // 1-bit input: Buffer input
   .IO(SCL), // 1-bit inout: Buffer inout (connect directly to top-level port)
   .T(SDA_tx_top)    // 1-bit input: 3-state enable input
);
`else
    assign SCL = SCL_tx_top ? 1'bz : 1'b0;
    assign SCL_in = SCL;
    assign SDA = SDA_tx_top ? 1'bz : 1'b0;
    assign SDA_in = SDA;
`endif


i2c_master i2c_inst (
    .clk(CLK100MHZ),
    .rst(~rst),
    .start(start_i2c),
    .dac_addr(current_addr),
    .data_send(current_data),
    .bytes_send(2),
    .bytes_receive(0),
    .SDA(SDA_in), // input
    .SCL(SCL_in), // input
    .SCL_tx_out(SCL_tx_top), // output -> IOBUF
    .SDA_tx_out(SDA_tx_top), // output ->  IOBUF
    .i2c_busy(i2c_busy),
    .data_received(data_received)
);

//====== to go through ILA comfortabely, sice mi window is narrow======
(* mark_debug = "true" *) logic [31:0] sample_cnt;

always_ff @(posedge CLK100MHZ) begin
    if(rst)
        sample_cnt <= 0;
    else if(sample_send)
        sample_cnt <= sample_cnt + 1;
end


endmodule

writer.writerow([{data_count:.10f}, {y0/scale:.10f}, {y1/scale:.10f}, {y2/scale:.10f}, {y3/scale:.10f}, {y4/scale:.10f}, dt/100.0])
