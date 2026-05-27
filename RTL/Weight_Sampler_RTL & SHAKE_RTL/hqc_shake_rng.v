// SPDX-License-Identifier: MIT
//
// Verilog-2001 HQC-128 SHAKE/RNG subsystem.
//
// Modes:
//   4'h1: SHAKE-PRNG init
//   4'h2: SHAKE-PRNG squeeze
//   4'h3: SeedExpander init
//   4'h4: SeedExpander squeeze
//   4'h6: SHAKE256-512 with domain separation G/H/K
//   4'hf: zeroize states

module hqc_shake_rng_v #(
    parameter integer RATE_BYTES    = 136,
    parameter integer HASH512_BYTES = 64
) (
    clk,
    rst_n,
    start,
    mode,
    domain,
    in_len_bytes,
    out_len_bytes,
    din_valid,
    din_ready,
    din_byte,
    dout_valid,
    dout_ready,
    dout_byte,
    busy,
    done,
    err_fault
);

    input clk;
    input rst_n;
    input start;
    input [3:0] mode; // PRNG_INIT; PRNG_SQZ; SEED_INIT; SEED_SQZ; HASH512_DS; ZEROIZE
    input [7:0] domain;
    input [15:0] in_len_bytes;
    input [15:0] out_len_bytes;

    input din_valid;
    output reg din_ready;
    input [7:0] din_byte;

    output reg dout_valid;
    input dout_ready;
    output reg [7:0] dout_byte;

    output busy;
    output reg done;
    output reg err_fault;

    localparam [3:0] MODE_PRNG_INIT  = 4'h1;
    localparam [3:0] MODE_PRNG_SQZ   = 4'h2;
    localparam [3:0] MODE_SEED_INIT  = 4'h3;
    localparam [3:0] MODE_SEED_SQZ   = 4'h4;
    localparam [3:0] MODE_HASH512_DS = 4'h6;
    localparam [3:0] MODE_ZEROIZE    = 4'hf;

    localparam [7:0] PRNG_DOMAIN         = 8'd1;
    localparam [7:0] SEEDEXPANDER_DOMAIN = 8'd2;
    localparam [7:0] RATE_BYTES_U8       = RATE_BYTES;
    localparam [7:0] RATE_LAST_U8        = RATE_BYTES - 1;

    localparam [4:0] ST_IDLE          = 5'd0;
    localparam [4:0] ST_CLEAR_WORK    = 5'd1;
    localparam [4:0] ST_LOAD_SQZ_CTX  = 5'd2;
    localparam [4:0] ST_ABSORB        = 5'd3;
    localparam [4:0] ST_APPEND_DOMAIN = 5'd4;
    localparam [4:0] ST_FINALIZE      = 5'd5;
    localparam [4:0] ST_PERM_START    = 5'd6;
    localparam [4:0] ST_PERM_WAIT     = 5'd7;
    localparam [4:0] ST_SQUEEZE_PREP  = 5'd8;
    localparam [4:0] ST_SQUEEZE       = 5'd9;
    localparam [4:0] ST_STORE_CTX     = 5'd10;
    localparam [4:0] ST_ZEROIZE       = 5'd11;
    localparam [4:0] ST_DONE          = 5'd12;
    localparam [4:0] ST_FAULT         = 5'd13;

    localparam [1:0] RET_ABSORB        = 2'd0;
    localparam [1:0] RET_APPEND_DOMAIN = 2'd1;
    localparam [1:0] RET_HASH_SQUEEZE  = 2'd2;
    localparam [1:0] RET_SQUEEZE       = 2'd3;

    reg [4:0] state_q;
    reg [4:0] state_d;
    reg [1:0] perm_return_q;

    reg [1599:0] work_state_q;
    reg [1599:0] prng_state_q;
    reg [1599:0] seed_state_q;

    reg [7:0] prng_out_pos_q;
    reg [7:0] seed_out_pos_q;
    reg [7:0] out_pos_q;
    reg [7:0] absorb_pos_q;

    reg [15:0] in_remaining_q;
    reg [15:0] out_remaining_q;
    reg [3:0] mode_q;
    reg [7:0] effective_domain_q;
    reg [15:0] watchdog_q;

    reg core_start;
    wire core_busy;
    wire core_done;
    wire [1599:0] core_state_out;

    assign busy = (state_q != ST_IDLE);

    hqc_keccak_f1600_core_v u_keccak_core (
        .clk       (clk),
        .rst_n     (rst_n),
        .start     (core_start),
        .state_in  (work_state_q),
        .busy      (core_busy),
        .done      (core_done),
        .state_out (core_state_out)
    );

    function is_init_mode;
        input [3:0] m;
        begin
            is_init_mode = (m == MODE_PRNG_INIT) ||
                           (m == MODE_SEED_INIT) ||
                           (m == MODE_HASH512_DS);
        end
    endfunction

    function is_squeeze_mode;
        input [3:0] m;
        begin
            is_squeeze_mode = (m == MODE_PRNG_SQZ) || (m == MODE_SEED_SQZ);
        end
    endfunction

    function [7:0] mode_domain;
        input [3:0] m;
        input [7:0] requested_domain;
        begin
            case (m)
                MODE_PRNG_INIT:  mode_domain = PRNG_DOMAIN;
                MODE_SEED_INIT:  mode_domain = SEEDEXPANDER_DOMAIN;
                MODE_HASH512_DS: mode_domain = requested_domain;
                default:         mode_domain = 8'd0;
            endcase
        end
    endfunction

    function valid_domain;
        input [3:0] m;
        input [7:0] requested_domain;
        begin
            case (m)
                MODE_PRNG_INIT:  valid_domain = 1'b1;
                MODE_SEED_INIT:  valid_domain = 1'b1;
                MODE_HASH512_DS: valid_domain = (requested_domain >= 8'd3) &&
                                                (requested_domain <= 8'd5);
                default:         valid_domain = 1'b1;
            endcase
        end
    endfunction

    function [15:0] selected_out_len;
        input [3:0] m;
        input [15:0] requested_len;
        begin
            if (m == MODE_HASH512_DS) begin
                selected_out_len = HASH512_BYTES;
            end else begin
                selected_out_len = requested_len;
            end
        end
    endfunction

    always @(*) begin
        state_d    = state_q;
        core_start = 1'b0;
        din_ready  = 1'b0;
        dout_valid = 1'b0;
        dout_byte  = 8'd0;

        case (state_q)
            ST_IDLE: begin
                if (start) begin
                    if (mode == MODE_ZEROIZE) begin
                        state_d = ST_ZEROIZE;
                    end else if (is_init_mode(mode) && valid_domain(mode, domain)) begin
                        state_d = ST_CLEAR_WORK;
                    end else if (is_squeeze_mode(mode)) begin
                        state_d = ST_LOAD_SQZ_CTX;
                    end else begin
                        state_d = ST_FAULT;
                    end
                end
            end

            ST_CLEAR_WORK: begin
                if (in_remaining_q == 16'd0) begin
                    state_d = ST_APPEND_DOMAIN;
                end else begin
                    state_d = ST_ABSORB;
                end
            end

            ST_LOAD_SQZ_CTX: begin
                if (out_remaining_q == 16'd0) begin
                    state_d = ST_STORE_CTX;
                end else begin
                    state_d = ST_SQUEEZE_PREP;
                end
            end

            ST_ABSORB: begin
                din_ready = 1'b1;
                if (din_valid) begin
                    if (absorb_pos_q == RATE_LAST_U8) begin
                        state_d = ST_PERM_START;
                    end else if (in_remaining_q == 16'd1) begin
                        state_d = ST_APPEND_DOMAIN;
                    end
                end
            end

            ST_APPEND_DOMAIN: begin
                if (absorb_pos_q == RATE_LAST_U8) begin
                    state_d = ST_PERM_START;
                end else begin
                    state_d = ST_FINALIZE;
                end
            end

            ST_FINALIZE: begin
                if (mode_q == MODE_HASH512_DS) begin
                    state_d = ST_PERM_START;
                end else begin
                    state_d = ST_STORE_CTX;
                end
            end

            ST_PERM_START: begin
                if (!core_busy) begin
                    core_start = 1'b1;
                    state_d = ST_PERM_WAIT;
                end
            end

            ST_PERM_WAIT: begin
                if (core_done) begin
                    case (perm_return_q)
                        RET_ABSORB: begin
                            if (in_remaining_q == 16'd0) begin
                                state_d = ST_APPEND_DOMAIN;
                            end else begin
                                state_d = ST_ABSORB;
                            end
                        end
                        RET_APPEND_DOMAIN: state_d = ST_FINALIZE;
                        RET_HASH_SQUEEZE:  state_d = ST_SQUEEZE;
                        default:           state_d = ST_SQUEEZE;
                    endcase
                end
            end

            ST_SQUEEZE_PREP: begin
                if (out_pos_q == RATE_BYTES_U8) begin
                    state_d = ST_PERM_START;
                end else begin
                    state_d = ST_SQUEEZE;
                end
            end

            ST_SQUEEZE: begin
                dout_valid = (out_remaining_q != 16'd0);
                dout_byte = work_state_q[8*out_pos_q +: 8];

                if (out_remaining_q == 16'd0) begin
                    state_d = ST_STORE_CTX;
                end else if (dout_valid && dout_ready && (out_remaining_q == 16'd1)) begin
                    state_d = ST_STORE_CTX;
                end else if (dout_valid && dout_ready && (out_pos_q == RATE_LAST_U8)) begin
                    state_d = ST_SQUEEZE_PREP;
                end
            end

            ST_STORE_CTX: begin
                state_d = ST_DONE;
            end

            ST_ZEROIZE: begin
                state_d = ST_DONE;
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
            work_state_q       <= 1600'd0;
            prng_state_q       <= 1600'd0;
            seed_state_q       <= 1600'd0;
            prng_out_pos_q     <= RATE_BYTES_U8;
            seed_out_pos_q     <= RATE_BYTES_U8;
            out_pos_q          <= RATE_BYTES_U8;
            absorb_pos_q       <= 8'd0;
            in_remaining_q     <= 16'd0;
            out_remaining_q    <= 16'd0;
            mode_q             <= 4'd0;
            effective_domain_q <= 8'd0;
            perm_return_q      <= RET_ABSORB;
            watchdog_q         <= 16'd0;
            done               <= 1'b0;
            err_fault          <= 1'b0;
        end else begin
            state_q <= state_d;
            done <= 1'b0;

            if ((state_q != ST_IDLE) && (state_q != ST_DONE) && (state_q != ST_FAULT)) begin
                watchdog_q <= watchdog_q + 16'd1;
                if (watchdog_q == 16'hffff) begin
                    err_fault <= 1'b1;
                    state_q <= ST_FAULT;
                end
            end

            case (state_q)
                ST_IDLE: begin
                    if (start) begin
                        mode_q             <= mode;
                        effective_domain_q <= mode_domain(mode, domain);
                        in_remaining_q     <= in_len_bytes;
                        out_remaining_q    <= selected_out_len(mode, out_len_bytes);
                        absorb_pos_q       <= 8'd0;
                        watchdog_q         <= 16'd0;
                        err_fault          <= 1'b0;
                    end
                end

                ST_CLEAR_WORK: begin
                    work_state_q <= 1600'd0;
                    out_pos_q <= RATE_BYTES_U8;
                end

                ST_LOAD_SQZ_CTX: begin
                    if (mode_q == MODE_PRNG_SQZ) begin
                        work_state_q <= prng_state_q;
                        out_pos_q <= prng_out_pos_q;
                    end else begin
                        work_state_q <= seed_state_q;
                        out_pos_q <= seed_out_pos_q;
                    end
                end

                ST_ABSORB: begin
                    if (din_valid && din_ready) begin
                        work_state_q[8*absorb_pos_q +: 8] <=
                            work_state_q[8*absorb_pos_q +: 8] ^ din_byte;
                        in_remaining_q <= in_remaining_q - 16'd1;

                        if (absorb_pos_q == RATE_LAST_U8) begin
                            absorb_pos_q <= 8'd0;
                            perm_return_q <= RET_ABSORB;
                        end else begin
                            absorb_pos_q <= absorb_pos_q + 8'd1;
                        end
                    end
                end

                ST_APPEND_DOMAIN: begin
                    work_state_q[8*absorb_pos_q +: 8] <=
                        work_state_q[8*absorb_pos_q +: 8] ^ effective_domain_q;

                    if (absorb_pos_q == RATE_LAST_U8) begin
                        absorb_pos_q <= 8'd0;
                        perm_return_q <= RET_APPEND_DOMAIN;
                    end else begin
                        absorb_pos_q <= absorb_pos_q + 8'd1;
                    end
                end

                ST_FINALIZE: begin
                    if (absorb_pos_q == RATE_LAST_U8) begin
                        work_state_q[8*absorb_pos_q +: 8] <=
                            work_state_q[8*absorb_pos_q +: 8] ^ 8'h9f;
                    end else begin
                        work_state_q[8*absorb_pos_q +: 8] <=
                            work_state_q[8*absorb_pos_q +: 8] ^ 8'h1f;
                        work_state_q[8*(RATE_BYTES-1) +: 8] <=
                            work_state_q[8*(RATE_BYTES-1) +: 8] ^ 8'h80;
                    end

                    out_pos_q <= RATE_BYTES_U8;
                    if (mode_q == MODE_HASH512_DS) begin
                        perm_return_q <= RET_HASH_SQUEEZE;
                    end
                end

                ST_SQUEEZE_PREP: begin
                    if (out_pos_q == RATE_BYTES_U8) begin
                        perm_return_q <= RET_SQUEEZE;
                    end
                end

                ST_PERM_WAIT: begin
                    if (core_done) begin
                        work_state_q <= core_state_out;
                        if ((perm_return_q == RET_HASH_SQUEEZE) ||
                            (perm_return_q == RET_SQUEEZE)) begin
                            out_pos_q <= 8'd0;
                        end
                    end
                end

                ST_SQUEEZE: begin
                    if (dout_valid && dout_ready) begin
                        out_remaining_q <= out_remaining_q - 16'd1;
                        if (out_pos_q == RATE_LAST_U8) begin
                            out_pos_q <= RATE_BYTES_U8;
                        end else begin
                            out_pos_q <= out_pos_q + 8'd1;
                        end
                    end
                end

                ST_STORE_CTX: begin
                    if ((mode_q == MODE_PRNG_INIT) || (mode_q == MODE_PRNG_SQZ)) begin
                        prng_state_q <= work_state_q;
                        prng_out_pos_q <= out_pos_q;
                    end else if ((mode_q == MODE_SEED_INIT) || (mode_q == MODE_SEED_SQZ)) begin
                        seed_state_q <= work_state_q;
                        seed_out_pos_q <= out_pos_q;
                    end
                end

                ST_ZEROIZE: begin
                    work_state_q <= 1600'd0;
                    prng_state_q <= 1600'd0;
                    seed_state_q <= 1600'd0;
                    prng_out_pos_q <= RATE_BYTES_U8;
                    seed_out_pos_q <= RATE_BYTES_U8;
                    out_pos_q <= RATE_BYTES_U8;
                    absorb_pos_q <= 8'd0;
                end

                ST_DONE: begin
                    done <= 1'b1;
                end

                ST_FAULT: begin
                    err_fault <= 1'b1;
                    work_state_q <= 1600'd0;
                end

                default: begin
                end
            endcase
        end
    end

endmodule
