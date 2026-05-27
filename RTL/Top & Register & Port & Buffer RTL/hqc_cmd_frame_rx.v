`timescale 1ns / 1ps
// Command frame receiver:
//   0xA5, opcode, flags, len_lo, len_hi, addr_lo, addr_hi, payload..., crc_lo, crc_hi
// CRC covers opcode through payload, initial value 0xffff.
module hqc_cmd_frame_rx (
    input             clk,
    input             rst_n,

    input             byte_valid,
    output            byte_ready,
    input      [7:0]  byte_data,

    output reg        cmd_valid,
    input             cmd_ready,
    output reg [7:0]  cmd_opcode,
    output reg [7:0]  cmd_flags,
    output reg [15:0] cmd_length,
    output reg [15:0] cmd_addr,

    output reg        mem_wr_en,
    output reg [15:0] mem_wr_addr,
    output reg [7:0]  mem_wr_data,

    output reg        err_bad_crc,
    output reg        err_bad_len,
    output reg        err_unexpected
);
    localparam [7:0] SOF = 8'ha5;
    localparam [7:0] OPCODE_WRITE_MEM = 8'h10;

    localparam [3:0] ST_IDLE  = 4'd0;
    localparam [3:0] ST_OP    = 4'd1;
    localparam [3:0] ST_FLAGS = 4'd2;
    localparam [3:0] ST_LEN0  = 4'd3;
    localparam [3:0] ST_LEN1  = 4'd4;
    localparam [3:0] ST_ADDR0 = 4'd5;
    localparam [3:0] ST_ADDR1 = 4'd6;
    localparam [3:0] ST_PAY   = 4'd7;
    localparam [3:0] ST_CRC0  = 4'd8;
    localparam [3:0] ST_CRC1  = 4'd9;
    localparam [3:0] ST_WAIT  = 4'd10;

    reg [3:0] state_q;
    reg [15:0] crc_q;
    reg [15:0] rx_crc_q;
    reg [15:0] pay_count_q;

    wire byte_fire = byte_valid && byte_ready;
    wire has_payload = (cmd_opcode == OPCODE_WRITE_MEM);
    assign byte_ready = (state_q != ST_WAIT);

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

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q        <= ST_IDLE;
            crc_q          <= 16'hffff;
            rx_crc_q       <= 16'd0;
            pay_count_q    <= 16'd0;
            cmd_valid      <= 1'b0;
            cmd_opcode     <= 8'd0;
            cmd_flags      <= 8'd0;
            cmd_length     <= 16'd0;
            cmd_addr       <= 16'd0;
            mem_wr_en      <= 1'b0;
            mem_wr_addr    <= 16'd0;
            mem_wr_data    <= 8'd0;
            err_bad_crc    <= 1'b0;
            err_bad_len    <= 1'b0;
            err_unexpected <= 1'b0;
        end else begin
            mem_wr_en      <= 1'b0;
            err_bad_crc    <= 1'b0;
            err_bad_len    <= 1'b0;
            err_unexpected <= 1'b0;

            if (cmd_valid && cmd_ready) begin
                cmd_valid <= 1'b0;
                state_q   <= ST_IDLE;
            end

            if (byte_fire) begin
                case (state_q)
                    ST_IDLE: begin
                        if (byte_data == SOF) begin
                            crc_q       <= 16'hffff;
                            pay_count_q <= 16'd0;
                            state_q     <= ST_OP;
                        end
                    end
                    ST_OP: begin
                        cmd_opcode <= byte_data;
                        crc_q      <= crc16_next(crc_q, byte_data);
                        state_q    <= ST_FLAGS;
                    end
                    ST_FLAGS: begin
                        cmd_flags <= byte_data;
                        crc_q     <= crc16_next(crc_q, byte_data);
                        state_q   <= ST_LEN0;
                    end
                    ST_LEN0: begin
                        cmd_length[7:0] <= byte_data;
                        crc_q           <= crc16_next(crc_q, byte_data);
                        state_q         <= ST_LEN1;
                    end
                    ST_LEN1: begin
                        cmd_length[15:8] <= byte_data;
                        crc_q            <= crc16_next(crc_q, byte_data);
                        state_q          <= ST_ADDR0;
                    end
                    ST_ADDR0: begin
                        cmd_addr[7:0] <= byte_data;
                        crc_q         <= crc16_next(crc_q, byte_data);
                        state_q       <= ST_ADDR1;
                    end
                    ST_ADDR1: begin
                        cmd_addr[15:8] <= byte_data;
                        crc_q          <= crc16_next(crc_q, byte_data);
                        if (has_payload && (cmd_length != 16'd0)) begin
                            state_q <= ST_PAY;
                        end else begin
                            state_q <= ST_CRC0;
                        end
                    end
                    ST_PAY: begin
                        mem_wr_en   <= 1'b1;
                        mem_wr_addr <= cmd_addr + pay_count_q;
                        mem_wr_data <= byte_data;
                        crc_q       <= crc16_next(crc_q, byte_data);
                        if (pay_count_q == cmd_length - 1'b1) begin
                            pay_count_q <= 16'd0;
                            state_q     <= ST_CRC0;
                        end else begin
                            pay_count_q <= pay_count_q + 1'b1;
                        end
                    end
                    ST_CRC0: begin
                        rx_crc_q[7:0] <= byte_data;
                        state_q       <= ST_CRC1;
                    end
                    ST_CRC1: begin
                        rx_crc_q[15:8] <= byte_data;
                        if ({byte_data, rx_crc_q[7:0]} == crc_q) begin
                            cmd_valid <= 1'b1;
                            state_q   <= ST_WAIT;
                        end else begin
                            err_bad_crc <= 1'b1;
                            state_q     <= ST_IDLE;
                        end
                    end
                    default: begin
                        err_unexpected <= 1'b1;
                        state_q        <= ST_IDLE;
                    end
                endcase
            end
        end
    end
endmodule
