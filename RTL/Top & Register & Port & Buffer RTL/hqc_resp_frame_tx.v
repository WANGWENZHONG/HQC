`timescale 1ns / 1ps
// Response frame transmitter:
//   0x5A, opcode, status, len_lo, len_hi, addr_lo, addr_hi, payload..., crc_lo, crc_hi
module hqc_resp_frame_tx (
    input             clk,
    input             rst_n,

    input             start,
    output reg        busy,
    output reg        done,
    input      [7:0]  opcode,
    input      [7:0]  status,
    input      [15:0] length,
    input      [15:0] base_addr,

    output reg        mem_rd_en,
    output reg [15:0] mem_rd_addr,
    input      [7:0]  mem_rd_data,

    output reg        out_valid,
    input             out_ready,
    output reg [7:0]  out_data
);
    localparam [7:0] SOF = 8'h5a;

    localparam [3:0] ST_IDLE     = 4'd0;
    localparam [3:0] ST_SOF      = 4'd1;
    localparam [3:0] ST_OP       = 4'd2;
    localparam [3:0] ST_STATUS   = 4'd3;
    localparam [3:0] ST_LEN0     = 4'd4;
    localparam [3:0] ST_LEN1     = 4'd5;
    localparam [3:0] ST_ADDR0    = 4'd6;
    localparam [3:0] ST_ADDR1    = 4'd7;
    localparam [3:0] ST_PAY_REQ  = 4'd8;
    localparam [3:0] ST_PAY_WAIT = 4'd9;
    localparam [3:0] ST_PAY_SEND = 4'd10;
    localparam [3:0] ST_CRC0     = 4'd11;
    localparam [3:0] ST_CRC1     = 4'd12;
    localparam [3:0] ST_DONE     = 4'd13;

    reg [3:0] state_q;
    reg [7:0] opcode_q;
    reg [7:0] status_q;
    reg [15:0] length_q;
    reg [15:0] base_addr_q;
    reg [15:0] count_q;
    reg [15:0] crc_q;

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
            state_q     <= ST_IDLE;
            opcode_q    <= 8'd0;
            status_q    <= 8'd0;
            length_q    <= 16'd0;
            base_addr_q <= 16'd0;
            count_q     <= 16'd0;
            crc_q       <= 16'hffff;
            mem_rd_en   <= 1'b0;
            mem_rd_addr <= 16'd0;
            out_valid   <= 1'b0;
            out_data    <= 8'd0;
            busy        <= 1'b0;
            done        <= 1'b0;
        end else begin
            mem_rd_en <= 1'b0;
            done      <= 1'b0;

            if (start && !busy) begin
                opcode_q    <= opcode;
                status_q    <= status;
                length_q    <= length;
                base_addr_q <= base_addr;
                count_q     <= 16'd0;
                crc_q       <= 16'hffff;
                state_q     <= ST_SOF;
                busy        <= 1'b1;
                out_valid   <= 1'b0;
            end else if (busy) begin
                if (!out_valid) begin
                    case (state_q)
                        ST_SOF: begin
                            out_data  <= SOF;
                            out_valid <= 1'b1;
                        end
                        ST_OP: begin
                            out_data  <= opcode_q;
                            out_valid <= 1'b1;
                        end
                        ST_STATUS: begin
                            out_data  <= status_q;
                            out_valid <= 1'b1;
                        end
                        ST_LEN0: begin
                            out_data  <= length_q[7:0];
                            out_valid <= 1'b1;
                        end
                        ST_LEN1: begin
                            out_data  <= length_q[15:8];
                            out_valid <= 1'b1;
                        end
                        ST_ADDR0: begin
                            out_data  <= base_addr_q[7:0];
                            out_valid <= 1'b1;
                        end
                        ST_ADDR1: begin
                            out_data  <= base_addr_q[15:8];
                            out_valid <= 1'b1;
                        end
                        ST_PAY_REQ: begin
                            mem_rd_en   <= 1'b1;
                            mem_rd_addr <= base_addr_q + count_q;
                            state_q     <= ST_PAY_WAIT;
                        end
                        ST_PAY_WAIT: begin
                            state_q     <= ST_PAY_SEND;
                        end
                        ST_PAY_SEND: begin
                            out_data  <= mem_rd_data;
                            out_valid <= 1'b1;
                        end
                        ST_CRC0: begin
                            out_data  <= crc_q[7:0];
                            out_valid <= 1'b1;
                        end
                        ST_CRC1: begin
                            out_data  <= crc_q[15:8];
                            out_valid <= 1'b1;
                        end
                        ST_DONE: begin
                            busy    <= 1'b0;
                            done    <= 1'b1;
                            state_q <= ST_IDLE;
                        end
                        default: begin
                            state_q <= ST_DONE;
                        end
                    endcase
                end else if (out_ready) begin
                    out_valid <= 1'b0;
                    case (state_q)
                        ST_SOF: begin
                            state_q <= ST_OP;
                        end
                        ST_OP: begin
                            crc_q   <= crc16_next(crc_q, opcode_q);
                            state_q <= ST_STATUS;
                        end
                        ST_STATUS: begin
                            crc_q   <= crc16_next(crc_q, status_q);
                            state_q <= ST_LEN0;
                        end
                        ST_LEN0: begin
                            crc_q   <= crc16_next(crc_q, length_q[7:0]);
                            state_q <= ST_LEN1;
                        end
                        ST_LEN1: begin
                            crc_q   <= crc16_next(crc_q, length_q[15:8]);
                            state_q <= ST_ADDR0;
                        end
                        ST_ADDR0: begin
                            crc_q   <= crc16_next(crc_q, base_addr_q[7:0]);
                            state_q <= ST_ADDR1;
                        end
                        ST_ADDR1: begin
                            crc_q <= crc16_next(crc_q, base_addr_q[15:8]);
                            if (length_q == 16'd0)
                                state_q <= ST_CRC0;
                            else
                                state_q <= ST_PAY_REQ;
                        end
                        ST_PAY_SEND: begin
                            crc_q <= crc16_next(crc_q, out_data);
                            if (count_q == length_q - 1'b1) begin
                                count_q <= 16'd0;
                                state_q <= ST_CRC0;
                            end else begin
                                count_q <= count_q + 1'b1;
                                state_q <= ST_PAY_REQ;
                            end
                        end
                        ST_CRC0: state_q <= ST_CRC1;
                        ST_CRC1: state_q <= ST_DONE;
                        default: state_q <= ST_DONE;
                    endcase
                end
            end
        end
    end
endmodule
