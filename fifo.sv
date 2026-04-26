import types_pkg::*;


//--------------------FIFO =------------------
    module fifo #(parameter SIZE = 64)
    (
        input logic clk,
        input logic rst,
        input logic wr_en, //write enable input
        input logic rd_en, //read enable input
        input DATA wr_data,

        output DATA rd_data,
        output logic full,
        output logic empty

    );
        DATA buffer [0:SIZE-1];

        logic [$clog2(SIZE):0] wr_ptr, rd_ptr, count; //wskaźnmiki

        assign full  = (count == SIZE); 
        assign empty = (count == 0); 


        initial begin
            for (int i = 0; i < SIZE; i++)
                buffer[i] = '0;
        end

        always_ff @(posedge clk) begin

            if(rst) begin
                wr_ptr<=0;
                rd_ptr<=0;
                count<=0;
                rd_data <= 0;
                // for(int i = 0; i < SIZE; i++)
                //     buffer[i] <= '0;
            end else begin
                //saving!!
                if (wr_en && !full) begin
                    buffer[wr_ptr] <= wr_data;
                    wr_ptr <= wr_ptr+1;
                    //count <= count +1; //odp za rozmiar buffera
                end
                //read
                if(rd_en && !empty) begin //if(rd_en && !empty) begin
                    rd_data <= buffer[rd_ptr];
                    rd_ptr <= rd_ptr +1;
                    //count <= count - 1; //oproznianie (sie hiih)
                end

                case ({wr_en && !full, rd_en && !empty})
                    2'b10:   count <= count + 1;
                    2'b01:   count <= count - 1;
                    default: count <= count;
                endcase
            end 
        end

    endmodule


//------------------------------------------------------
