`timescale 1ns / 1ps
// Byte-parallel CRC-16/CCITT update, polynomial x^16 + x^12 + x^5 + 1.
module hqc_crc16_ccitt (
    input      [15:0] crc_in,
    input      [7:0]  data_in,
    output     [15:0] crc_out
);
    function [15:0] crc16_next;
        input [15:0] crc;
        input [7:0]  data;
        integer i;
        reg [15:0] c;
        begin
            c = crc ^ {data, 8'h00};
            for (i = 0; i < 8; i = i + 1) begin
                if (c[15])
                    c = (c << 1) ^ 16'h1021;
                else
                    c = (c << 1);
            end
            crc16_next = c;
        end
    endfunction

    assign crc_out = crc16_next(crc_in, data_in);
endmodule
