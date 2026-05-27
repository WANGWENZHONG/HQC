`timescale 1ns / 1ps
// Concrete adapter for the supplied SHAKE SeedExpander and fixed-weight sampler.
module hqc_rng_sampler_cluster #(
    parameter integer SEED_BYTES    = 32,
    parameter integer RNG_OUT_BYTES = 768
) (
    input             clk,
    input             rst_n,
    input             start,
    input      [255:0] seed,
    input      [6:0]  weight,
    input             dense_enable,

    output reg        busy,
    output reg        done,
    output reg        err_fault,

    output            coord_wr_en,
    output     [6:0]  coord_wr_addr,
    output     [14:0] coord_wr_data,
    output            vec_wr_en,
    output     [7:0]  vec_wr_addr,
    output     [127:0] vec_wr_data
);
    localparam [3:0] ST_IDLE        = 4'd0;
    localparam [3:0] ST_INIT_START  = 4'd1;
    localparam [3:0] ST_INIT_FEED   = 4'd2;
    localparam [3:0] ST_INIT_WAIT   = 4'd3;
    localparam [3:0] ST_SQZ_START   = 4'd4;
    localparam [3:0] ST_RUN         = 4'd5;
    localparam [3:0] ST_DRAIN       = 4'd6;
    localparam [3:0] ST_DONE        = 4'd7;
    localparam [3:0] ST_FAULT       = 4'd8;

    reg [3:0] state_q;
    reg [5:0] seed_idx_q;
    reg       rng_start;
    reg [3:0] rng_mode;
    reg       sampler_start;
    localparam [15:0] SEED_BYTES_U16 = SEED_BYTES;
    localparam [15:0] RNG_OUT_BYTES_U16 = RNG_OUT_BYTES;

    wire rng_din_ready;
    wire rng_dout_valid;
    wire rng_dout_ready;
    wire [7:0] rng_dout_byte;
    wire rng_busy;
    wire rng_done;
    wire rng_fault;

    wire sampler_rand_ready;
    wire sampler_busy;
    wire sampler_done;
    wire sampler_fault;

    wire rng_din_valid = (state_q == ST_INIT_FEED) && (seed_idx_q < SEED_BYTES);
    wire [7:0] rng_din_byte = seed[8*seed_idx_q +: 8];
    assign rng_dout_ready = (state_q == ST_RUN) ? sampler_rand_ready :
                            (state_q == ST_DRAIN);

    hqc_shake_rng_v u_shake_rng (
        .clk           (clk),
        .rst_n         (rst_n),
        .start         (rng_start),
        .mode          (rng_mode),
        .domain        (8'd2),
        .in_len_bytes  (SEED_BYTES_U16),
        .out_len_bytes (RNG_OUT_BYTES_U16),
        .din_valid     (rng_din_valid),
        .din_ready     (rng_din_ready),
        .din_byte      (rng_din_byte),
        .dout_valid    (rng_dout_valid),
        .dout_ready    (rng_dout_ready),
        .dout_byte     (rng_dout_byte),
        .busy          (rng_busy),
        .done          (rng_done),
        .err_fault     (rng_fault)
    );

    hqc_fixed_weight_sampler_v u_sampler (
        .clk           (clk),
        .rst_n         (rst_n),
        .start         (sampler_start),
        .weight        (weight),
        .dense_enable  (dense_enable),
        .rand_valid    ((state_q == ST_RUN) && rng_dout_valid),
        .rand_ready    (sampler_rand_ready),
        .rand_byte     (rng_dout_byte),
        .coord_wr_en   (coord_wr_en),
        .coord_wr_addr (coord_wr_addr),
        .coord_wr_data (coord_wr_data),
        .vec_wr_en     (vec_wr_en),
        .vec_wr_addr   (vec_wr_addr),
        .vec_wr_data   (vec_wr_data),
        .busy          (sampler_busy),
        .done          (sampler_done),
        .err_fault     (sampler_fault)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q       <= ST_IDLE;
            seed_idx_q    <= 6'd0;
            rng_start     <= 1'b0;
            rng_mode      <= 4'd0;
            sampler_start <= 1'b0;
            busy          <= 1'b0;
            done          <= 1'b0;
            err_fault     <= 1'b0;
        end else begin
            rng_start     <= 1'b0;
            sampler_start <= 1'b0;
            done          <= 1'b0;

            case (state_q)
                ST_IDLE: begin
                    busy      <= 1'b0;
                    seed_idx_q <= 6'd0;
                    err_fault <= 1'b0;
                    if (start) begin
                        busy    <= 1'b1;
                        state_q <= ST_INIT_START;
                    end
                end
                ST_INIT_START: begin
                    rng_start <= 1'b1;
                    rng_mode  <= 4'h3;
                    state_q   <= ST_INIT_FEED;
                end
                ST_INIT_FEED: begin
                    if (rng_fault) begin
                        state_q <= ST_FAULT;
                    end else if (rng_din_valid && rng_din_ready) begin
                        if (seed_idx_q == SEED_BYTES-1) begin
                            seed_idx_q <= 6'd0;
                            state_q    <= ST_INIT_WAIT;
                        end else begin
                            seed_idx_q <= seed_idx_q + 1'b1;
                        end
                    end
                end
                ST_INIT_WAIT: begin
                    if (rng_fault) begin
                        state_q <= ST_FAULT;
                    end else if (rng_done) begin
                        state_q <= ST_SQZ_START;
                    end
                end
                ST_SQZ_START: begin
                    rng_start     <= 1'b1;
                    rng_mode      <= 4'h4;
                    sampler_start <= 1'b1;
                    state_q       <= ST_RUN;
                end
                ST_RUN: begin
                    if (rng_fault || sampler_fault || (rng_done && !sampler_done)) begin
                        state_q <= ST_FAULT;
                    end else if (sampler_done) begin
                        state_q <= ST_DRAIN;
                    end
                end
                ST_DRAIN: begin
                    if (rng_fault) begin
                        state_q <= ST_FAULT;
                    end else if (rng_done) begin
                        state_q <= ST_DONE;
                    end
                end
                ST_DONE: begin
                    busy    <= 1'b0;
                    done    <= 1'b1;
                    state_q <= ST_IDLE;
                end
                ST_FAULT: begin
                    busy      <= 1'b0;
                    err_fault <= 1'b1;
                    done      <= 1'b1;
                    state_q   <= ST_IDLE;
                end
                default: begin
                    state_q <= ST_FAULT;
                end
            endcase
        end
    end
endmodule
