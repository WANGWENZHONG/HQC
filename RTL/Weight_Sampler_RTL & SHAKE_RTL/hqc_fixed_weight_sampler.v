// SPDX-License-Identifier: MIT
//
// Verilog-2001 fixed-weight vector sampler for HQC-128.
//
// It consumes SeedExpander bytes, forms 24-bit candidates, applies rejection
// sampling, checks duplicates with an internal bitmap, and emits sparse
// coordinates plus an optional dense 128-bit block vector.
//
// Dense vector format after this modification:
//   - vec_wr_data is 128 bits = 16 bytes per block
//   - vec_wr_addr indexes 128-bit blocks
//   - VEC_BLOCKS = ceil(N / 128) = 139 for N = 17669
//   - vec_wr_data[0] corresponds to vector bit vec_wr_addr*128 + 0
//   - vec_wr_data[127] corresponds to vector bit vec_wr_addr*128 + 127
//   - For N = 17669, only vec block 138 bits [4:0] are valid.

module hqc_fixed_weight_sampler_v #(
    parameter integer N              = 17669,
    parameter integer VEC_BLOCKS     = 139,
    parameter integer MAX_WEIGHT     = 75,
    parameter integer THRESHOLD      = 16767881,
    parameter integer MAX_CANDIDATES = 256,
    parameter integer VEC_ADDR_W     = 8,
    parameter integer COORD_ADDR_W   = 7
) (
    clk,
    rst_n,
    start,
    weight,
    dense_enable,
    rand_valid,
    rand_ready,
    rand_byte,
    coord_wr_en,
    coord_wr_addr,
    coord_wr_data,
    vec_wr_en,
    vec_wr_addr,
    vec_wr_data,
    busy,
    done,
    err_fault
);

    input clk;
    input rst_n;
    input start;
    input [6:0] weight;
    input dense_enable;
    input rand_valid;
    output reg rand_ready;
    input [7:0] rand_byte;

    output reg coord_wr_en;
    output reg [COORD_ADDR_W-1:0] coord_wr_addr;
    output reg [14:0] coord_wr_data;

    output reg vec_wr_en;
    output reg [VEC_ADDR_W-1:0] vec_wr_addr;
    output reg [127:0] vec_wr_data;

    output busy;
    output reg done;
    output reg err_fault;

    localparam [3:0] ST_IDLE         = 4'd0;
    localparam [3:0] ST_CHECK_WEIGHT = 4'd1;
    localparam [3:0] ST_CLEAR_VEC    = 4'd2;
    localparam [3:0] ST_CLEAR_COORD  = 4'd3;
    localparam [3:0] ST_GET_B0       = 4'd4;
    localparam [3:0] ST_GET_B1       = 4'd5;
    localparam [3:0] ST_GET_B2       = 4'd6;
    localparam [3:0] ST_REDUCE       = 4'd7;
    localparam [3:0] ST_READ_BITMAP  = 4'd8;
    localparam [3:0] ST_WRITE_MASKED = 4'd9;
    localparam [3:0] ST_DONE         = 4'd10;
    localparam [3:0] ST_FAULT        = 4'd11;

    localparam [23:0] THRESHOLD_U24 = THRESHOLD;

    reg [3:0] state_q;
    reg [3:0] state_d;

    reg [127:0] bitmap_q [0:VEC_BLOCKS-1];

    reg [6:0] weight_q;
    reg [6:0] accepted_q;
    reg [15:0] candidate_count_q;
    reg [23:0] candidate_q;
    reg [14:0] pos_q;
    reg threshold_ok_q;
    reg [127:0] bitmap_block_q;
    reg [VEC_ADDR_W-1:0] block_addr_q;
    reg [127:0] bit_mask_q;
    reg [VEC_ADDR_W-1:0] clear_vec_addr_q;
    reg [COORD_ADDR_W-1:0] clear_coord_addr_q;
    reg dense_enable_q;

    wire duplicate;
    wire accept_now;
    wire [14:0] candidate_pos;
    wire [VEC_ADDR_W-1:0] candidate_block_addr;
    wire [127:0] candidate_bit_mask;

    integer i;

    assign busy = (state_q != ST_IDLE);
    assign duplicate = |(bitmap_block_q & bit_mask_q);
    assign accept_now = threshold_ok_q && !duplicate;
    assign candidate_pos = candidate_q % N;
    assign candidate_block_addr = candidate_pos >> 7;
    assign candidate_bit_mask = 128'h1 << candidate_pos[6:0];

    always @(*) begin
        state_d       = state_q;
        rand_ready    = 1'b0;
        coord_wr_en   = 1'b0;
        coord_wr_addr = {COORD_ADDR_W{1'b0}};
        coord_wr_data = 15'd0;
        vec_wr_en     = 1'b0;
        vec_wr_addr   = {VEC_ADDR_W{1'b0}};
        vec_wr_data   = 128'd0;

        case (state_q)
            ST_IDLE: begin
                if (start) begin
                    state_d = ST_CHECK_WEIGHT;
                end
            end

            ST_CHECK_WEIGHT: begin
                if ((weight_q == 7'd66) || (weight_q == 7'd75)) begin
                    state_d = ST_CLEAR_VEC;
                end else begin
                    state_d = ST_FAULT;
                end
            end

            ST_CLEAR_VEC: begin
                vec_wr_en   = dense_enable_q;
                vec_wr_addr = clear_vec_addr_q;
                vec_wr_data = 128'd0;
                if (clear_vec_addr_q == VEC_BLOCKS - 1) begin
                    state_d = ST_CLEAR_COORD;
                end
            end

            ST_CLEAR_COORD: begin
                coord_wr_en   = 1'b1;
                coord_wr_addr = clear_coord_addr_q;
                coord_wr_data = 15'd0;
                if (clear_coord_addr_q == MAX_WEIGHT - 1) begin
                    state_d = ST_GET_B0;
                end
            end

            ST_GET_B0: begin
                rand_ready = 1'b1;
                if (rand_valid) begin
                    state_d = ST_GET_B1;
                end
            end

            ST_GET_B1: begin
                rand_ready = 1'b1;
                if (rand_valid) begin
                    state_d = ST_GET_B2;
                end
            end

            ST_GET_B2: begin
                rand_ready = 1'b1;
                if (rand_valid) begin
                    state_d = ST_REDUCE;
                end
            end

            ST_REDUCE: begin
                state_d = ST_READ_BITMAP;
            end

            ST_READ_BITMAP: begin
                state_d = ST_WRITE_MASKED;
            end

            ST_WRITE_MASKED: begin
                if (accept_now) begin
                    coord_wr_en   = 1'b1;
                    coord_wr_addr = accepted_q[COORD_ADDR_W-1:0];
                    coord_wr_data = pos_q;

                    vec_wr_en   = dense_enable_q;
                    vec_wr_addr = block_addr_q;
                    vec_wr_data = bitmap_block_q | bit_mask_q;
                end

                if (candidate_count_q >= MAX_CANDIDATES - 1) begin
                    state_d = ST_FAULT;
                end else if (accept_now && (accepted_q + 7'd1 == weight_q)) begin
                    state_d = ST_DONE;
                end else begin
                    state_d = ST_GET_B0;
                end
            end

            ST_DONE: begin
                state_d = ST_IDLE;
            end

            ST_FAULT: begin
                state_d = ST_IDLE;
            end

            default: begin
                state_d = ST_FAULT;
            end
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q            <= ST_IDLE;
            weight_q           <= 7'd0;
            accepted_q         <= 7'd0;
            candidate_count_q  <= 16'd0;
            candidate_q        <= 24'd0;
            pos_q              <= 15'd0;
            threshold_ok_q     <= 1'b0;
            bitmap_block_q     <= 128'd0;
            block_addr_q       <= {VEC_ADDR_W{1'b0}};
            bit_mask_q         <= 128'd0;
            clear_vec_addr_q   <= {VEC_ADDR_W{1'b0}};
            clear_coord_addr_q <= {COORD_ADDR_W{1'b0}};
            dense_enable_q     <= 1'b0;
            done               <= 1'b0;
            err_fault          <= 1'b0;

            for (i = 0; i < VEC_BLOCKS; i = i + 1) begin
                bitmap_q[i] <= 128'd0;
            end
        end else begin
            state_q <= state_d;
            done    <= 1'b0;

            case (state_q)
                ST_IDLE: begin
                    if (start) begin
                        weight_q           <= weight;
                        dense_enable_q     <= dense_enable;
                        accepted_q         <= 7'd0;
                        candidate_count_q  <= 16'd0;
                        candidate_q        <= 24'd0;
                        pos_q              <= 15'd0;
                        threshold_ok_q     <= 1'b0;
                        bitmap_block_q     <= 128'd0;
                        block_addr_q       <= {VEC_ADDR_W{1'b0}};
                        bit_mask_q         <= 128'd0;
                        clear_vec_addr_q   <= {VEC_ADDR_W{1'b0}};
                        clear_coord_addr_q <= {COORD_ADDR_W{1'b0}};
                        err_fault          <= 1'b0;
                    end
                end

                ST_CLEAR_VEC: begin
                    bitmap_q[clear_vec_addr_q] <= 128'd0;
                    if (clear_vec_addr_q != VEC_BLOCKS - 1) begin
                        clear_vec_addr_q <= clear_vec_addr_q + 1'b1;
                    end
                end

                ST_CLEAR_COORD: begin
                    if (clear_coord_addr_q != MAX_WEIGHT - 1) begin
                        clear_coord_addr_q <= clear_coord_addr_q + 1'b1;
                    end
                end

                ST_GET_B0: begin
                    if (rand_valid && rand_ready) begin
                        candidate_q[23:16] <= rand_byte;
                    end
                end

                ST_GET_B1: begin
                    if (rand_valid && rand_ready) begin
                        candidate_q[15:8] <= rand_byte;
                    end
                end

                ST_GET_B2: begin
                    if (rand_valid && rand_ready) begin
                        candidate_q[7:0] <= rand_byte;
                    end
                end

                ST_REDUCE: begin
                    threshold_ok_q <= (candidate_q < THRESHOLD_U24);
                    pos_q          <= candidate_pos;
                    block_addr_q   <= candidate_block_addr;
                    bit_mask_q     <= candidate_bit_mask;
                end

                ST_READ_BITMAP: begin
                    bitmap_block_q <= bitmap_q[block_addr_q];
                end

                ST_WRITE_MASKED: begin
                    candidate_count_q <= candidate_count_q + 16'd1;

                    if (candidate_count_q >= MAX_CANDIDATES - 1) begin
                        err_fault <= 1'b1;
                    end else if (accept_now) begin
                        bitmap_q[block_addr_q] <= bitmap_block_q | bit_mask_q;
                        accepted_q <= accepted_q + 7'd1;
                    end
                end

                ST_DONE: begin
                    done <= 1'b1;
                end

                ST_FAULT: begin
                    err_fault <= 1'b1;
                end

                default: begin
                end
            endcase
        end
    end

endmodule