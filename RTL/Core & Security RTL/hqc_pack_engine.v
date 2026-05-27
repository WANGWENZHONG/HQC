`timescale 1ns / 1ps
// Generic byte copy/fill engine for pack, unpack, and zeroize flows.
module hqc_pack_engine (
    input             clk,
    input             rst_n,
    input             start,
    input      [1:0]  mode,       // 0: fill, 1: copy
    input      [15:0] src_addr,
    input      [15:0] dst_addr,
    input      [15:0] length,
    input      [7:0]  fill_byte,

    output reg        mem_en,
    output reg        mem_we,
    output reg [15:0] mem_addr,
    output reg [7:0]  mem_wdata,
    input      [7:0]  mem_rdata,

    output reg        busy,
    output reg        done,
    output reg        err_fault
);
    localparam [2:0] ST_IDLE  = 3'd0;
    localparam [2:0] ST_FILL  = 3'd1;
    localparam [2:0] ST_READ  = 3'd2;
    localparam [2:0] ST_WAIT  = 3'd3;
    localparam [2:0] ST_WRITE = 3'd4;
    localparam [2:0] ST_DONE  = 3'd5;

    reg [2:0] state_q;
    reg [15:0] count_q;
    reg [15:0] src_addr_q;
    reg [15:0] dst_addr_q;
    reg [15:0] length_q;
    reg [7:0] fill_byte_q;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q     <= ST_IDLE;
            count_q     <= 16'd0;
            src_addr_q  <= 16'd0;
            dst_addr_q  <= 16'd0;
            length_q    <= 16'd0;
            fill_byte_q <= 8'd0;
            mem_en      <= 1'b0;
            mem_we      <= 1'b0;
            mem_addr    <= 16'd0;
            mem_wdata   <= 8'd0;
            busy        <= 1'b0;
            done        <= 1'b0;
            err_fault   <= 1'b0;
        end else begin
            mem_en <= 1'b0;
            mem_we <= 1'b0;
            done   <= 1'b0;

            case (state_q)
                ST_IDLE: begin
                    busy      <= 1'b0;
                    err_fault <= 1'b0;
                    if (start) begin
                        busy        <= 1'b1;
                        count_q     <= 16'd0;
                        src_addr_q  <= src_addr;
                        dst_addr_q  <= dst_addr;
                        length_q    <= length;
                        fill_byte_q <= fill_byte;
                        if (length == 16'd0)
                            state_q <= ST_DONE;
                        else if (mode == 2'd0)
                            state_q <= ST_FILL;
                        else if (mode == 2'd1)
                            state_q <= ST_READ;
                        else begin
                            err_fault <= 1'b1;
                            state_q   <= ST_DONE;
                        end
                    end
                end
                ST_FILL: begin
                    mem_en    <= 1'b1;
                    mem_we    <= 1'b1;
                    mem_addr  <= dst_addr_q + count_q;
                    mem_wdata <= fill_byte_q;
                    if (count_q == length_q - 1'b1) begin
                        count_q <= 16'd0;
                        state_q <= ST_DONE;
                    end else begin
                        count_q <= count_q + 1'b1;
                    end
                end
                ST_READ: begin
                    mem_en   <= 1'b1;
                    mem_we   <= 1'b0;
                    mem_addr <= src_addr_q + count_q;
                    state_q  <= ST_WAIT;
                end
                ST_WAIT: begin
                    state_q  <= ST_WRITE;
                end
                ST_WRITE: begin
                    mem_en      <= 1'b1;
                    mem_we      <= 1'b1;
                    mem_addr    <= dst_addr_q + count_q;
                    mem_wdata   <= mem_rdata;
                    if (count_q == length_q - 1'b1) begin
                        count_q <= 16'd0;
                        state_q <= ST_DONE;
                    end else begin
                        count_q <= count_q + 1'b1;
                        state_q <= ST_READ;
                    end
                end
                ST_DONE: begin
                    busy    <= 1'b0;
                    done    <= 1'b1;
                    state_q <= ST_IDLE;
                end
                default: begin
                    err_fault <= 1'b1;
                    state_q   <= ST_DONE;
                end
            endcase
        end
    end
endmodule
