// SPDX-License-Identifier: MIT
//
// Verilog-2001 compact Keccak-f[1600] permutation core.
// One round is executed per clock cycle, so one permutation takes 24 cycles.

module hqc_keccak_f1600_core_v (
    clk,
    rst_n,
    start,
    state_in,
    busy,
    done,
    state_out
);

    input clk;
    input rst_n;
    input start;
    input [1599:0] state_in;

    output busy;
    output reg done;
    output [1599:0] state_out;

    localparam [4:0] ROUND_IDLE = 5'd31;
    localparam integer NROUNDS = 24;

    reg [63:0] state_q [0:24];
    reg [4:0] round_q;
    reg [1599:0] state_flat;
    reg [1599:0] next_flat;

    integer i;
    genvar gi;

    assign busy = (round_q != ROUND_IDLE);

    generate
        for (gi = 0; gi < 25; gi = gi + 1) begin : g_pack_state_out
            assign state_out[64*gi +: 64] = state_q[gi];
        end
    endgenerate

    function [63:0] rol64;
        input [63:0] value;
        input integer offset;
        begin
            if (offset == 0) begin
                rol64 = value;
            end else begin
                rol64 = (value << offset) | (value >> (64 - offset));
            end
        end
    endfunction

    function [63:0] round_constant;
        input [4:0] round;
        begin
            case (round)
                5'd0:  round_constant = 64'h0000_0000_0000_0001;
                5'd1:  round_constant = 64'h0000_0000_0000_8082;
                5'd2:  round_constant = 64'h8000_0000_0000_808a;
                5'd3:  round_constant = 64'h8000_0000_8000_8000;
                5'd4:  round_constant = 64'h0000_0000_0000_808b;
                5'd5:  round_constant = 64'h0000_0000_8000_0001;
                5'd6:  round_constant = 64'h8000_0000_8000_8081;
                5'd7:  round_constant = 64'h8000_0000_0000_8009;
                5'd8:  round_constant = 64'h0000_0000_0000_008a;
                5'd9:  round_constant = 64'h0000_0000_0000_0088;
                5'd10: round_constant = 64'h0000_0000_8000_8009;
                5'd11: round_constant = 64'h0000_0000_8000_000a;
                5'd12: round_constant = 64'h0000_0000_8000_808b;
                5'd13: round_constant = 64'h8000_0000_0000_008b;
                5'd14: round_constant = 64'h8000_0000_0000_8089;
                5'd15: round_constant = 64'h8000_0000_0000_8003;
                5'd16: round_constant = 64'h8000_0000_0000_8002;
                5'd17: round_constant = 64'h8000_0000_0000_0080;
                5'd18: round_constant = 64'h0000_0000_0000_800a;
                5'd19: round_constant = 64'h8000_0000_8000_000a;
                5'd20: round_constant = 64'h8000_0000_8000_8081;
                5'd21: round_constant = 64'h8000_0000_0000_8080;
                5'd22: round_constant = 64'h0000_0000_8000_0001;
                default: round_constant = 64'h8000_0000_8000_8008;
            endcase
        end
    endfunction

    function integer rho_offset;
        input integer x;
        input integer y;
        reg [5:0] key;
        begin
            key = {x[2:0], y[2:0]};
            case (key)
                {3'd0, 3'd0}: rho_offset = 0;
                {3'd1, 3'd0}: rho_offset = 1;
                {3'd2, 3'd0}: rho_offset = 62;
                {3'd3, 3'd0}: rho_offset = 28;
                {3'd4, 3'd0}: rho_offset = 27;
                {3'd0, 3'd1}: rho_offset = 36;
                {3'd1, 3'd1}: rho_offset = 44;
                {3'd2, 3'd1}: rho_offset = 6;
                {3'd3, 3'd1}: rho_offset = 55;
                {3'd4, 3'd1}: rho_offset = 20;
                {3'd0, 3'd2}: rho_offset = 3;
                {3'd1, 3'd2}: rho_offset = 10;
                {3'd2, 3'd2}: rho_offset = 43;
                {3'd3, 3'd2}: rho_offset = 25;
                {3'd4, 3'd2}: rho_offset = 39;
                {3'd0, 3'd3}: rho_offset = 41;
                {3'd1, 3'd3}: rho_offset = 45;
                {3'd2, 3'd3}: rho_offset = 15;
                {3'd3, 3'd3}: rho_offset = 21;
                {3'd4, 3'd3}: rho_offset = 8;
                {3'd0, 3'd4}: rho_offset = 18;
                {3'd1, 3'd4}: rho_offset = 2;
                {3'd2, 3'd4}: rho_offset = 61;
                {3'd3, 3'd4}: rho_offset = 56;
                default:       rho_offset = 14;
            endcase
        end
    endfunction

    function [1599:0] permute_round;
        input [1599:0] in_state;
        input [4:0] round;

        reg [63:0] a [0:24];
        reg [63:0] b [0:24];
        reg [63:0] c [0:4];
        reg [63:0] d [0:4];
        reg [63:0] e [0:24];
        reg [1599:0] out_state;
        integer x;
        integer y;
        integer dst_x;
        integer dst_y;

        begin
            for (y = 0; y < 5; y = y + 1) begin
                for (x = 0; x < 5; x = x + 1) begin
                    a[x + 5*y] = in_state[64*(x + 5*y) +: 64];
                end
            end

            for (x = 0; x < 5; x = x + 1) begin
                c[x] = a[x + 5*0] ^ a[x + 5*1] ^ a[x + 5*2] ^ a[x + 5*3] ^ a[x + 5*4];
            end

            for (x = 0; x < 5; x = x + 1) begin
                d[x] = c[(x + 4) % 5] ^ rol64(c[(x + 1) % 5], 1);
            end

            for (x = 0; x < 5; x = x + 1) begin
                for (y = 0; y < 5; y = y + 1) begin
                    a[x + 5*y] = a[x + 5*y] ^ d[x];
                end
            end

            for (x = 0; x < 5; x = x + 1) begin
                for (y = 0; y < 5; y = y + 1) begin
                    dst_x = y;
                    dst_y = (2*x + 3*y) % 5;
                    b[dst_x + 5*dst_y] = rol64(a[x + 5*y], rho_offset(x, y));
                end
            end

            for (y = 0; y < 5; y = y + 1) begin
                for (x = 0; x < 5; x = x + 1) begin
                    e[x + 5*y] = b[x + 5*y] ^
                                 ((~b[((x + 1) % 5) + 5*y]) &
                                      b[((x + 2) % 5) + 5*y]);
                end
            end

            e[0] = e[0] ^ round_constant(round);

            for (y = 0; y < 5; y = y + 1) begin
                for (x = 0; x < 5; x = x + 1) begin
                    out_state[64*(x + 5*y) +: 64] = e[x + 5*y];
                end
            end

            permute_round = out_state;
        end
    endfunction

    always @(*) begin
        for (i = 0; i < 25; i = i + 1) begin
            state_flat[64*i +: 64] = state_q[i];
        end
        next_flat = permute_round(state_flat, round_q);
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            round_q <= ROUND_IDLE;
            done    <= 1'b0;
            for (i = 0; i < 25; i = i + 1) begin
                state_q[i] <= 64'd0;
            end
        end else begin
            done <= 1'b0;

            if (start && !busy) begin
                for (i = 0; i < 25; i = i + 1) begin
                    state_q[i] <= state_in[64*i +: 64];
                end
                round_q <= 5'd0;
            end else if (busy) begin
                for (i = 0; i < 25; i = i + 1) begin
                    state_q[i] <= next_flat[64*i +: 64];
                end

                if (round_q == NROUNDS - 1) begin
                    round_q <= ROUND_IDLE;
                    done    <= 1'b1;
                end else begin
                    round_q <= round_q + 5'd1;
                end
            end
        end
    end

endmodule
