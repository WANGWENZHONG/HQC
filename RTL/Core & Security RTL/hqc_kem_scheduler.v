`timescale 1ns / 1ps
// HQC-128 KEM operation scheduler. It sequences the existing primitive
// engines through a compact micro-operation handshake.
module hqc_kem_scheduler (
    input             clk,
    input             rst_n,

    input             start,
    input      [7:0]  opcode,
    input      [15:0] host_addr,
    input      [15:0] host_length,
    input             zeroize_req,

    output            ready,
    output reg        busy,
    output reg        done,
    output reg [7:0]  err_status,
    output reg [7:0]  fault_status,

    output reg        prim_start,
    output reg [7:0]  prim_id,
    output reg [31:0] prim_arg,
    input             prim_done,
    input             prim_fault,
    input             prim_equal
);
    localparam [7:0] OPC_KEYGEN   = 8'h01;
    localparam [7:0] OPC_ENCAP    = 8'h02;
    localparam [7:0] OPC_DECAP    = 8'h03;
    localparam [7:0] OPC_ZEROIZE  = 8'h04;
    localparam [7:0] OPC_SELFTEST = 8'h05;

    localparam [7:0] P_HASH_H        = 8'h01;
    localparam [7:0] P_HASH_G        = 8'h02;
    localparam [7:0] P_HASH_K        = 8'h03;
    localparam [7:0] P_HASH_D        = 8'h04;
    localparam [7:0] P_SAMPLE_X      = 8'h10;
    localparam [7:0] P_SAMPLE_Y      = 8'h11;
    localparam [7:0] P_SAMPLE_R1     = 8'h12;
    localparam [7:0] P_SAMPLE_R2     = 8'h13;
    localparam [7:0] P_SAMPLE_E      = 8'h14;
    localparam [7:0] P_VECMUL_HY     = 8'h20;
    localparam [7:0] P_VECMUL_HR2    = 8'h21;
    localparam [7:0] P_VECMUL_SR2    = 8'h22;
    localparam [7:0] P_VECMUL_UY     = 8'h23;
    localparam [7:0] P_ENCODE        = 8'h30;
    localparam [7:0] P_DECODE        = 8'h31;
    localparam [7:0] P_CTCMP         = 8'h40;
    localparam [7:0] P_PACK_KEYS     = 8'h50;
    localparam [7:0] P_PACK_CT       = 8'h51;
    localparam [7:0] P_PACK_DECAP    = 8'h52;
    localparam [7:0] P_ZEROIZE       = 8'h60;
    localparam [7:0] P_SELFTEST      = 8'h70;

    localparam [6:0] ST_IDLE            = 7'd0;
    localparam [6:0] ST_DISPATCH        = 7'd1;
    localparam [6:0] ST_WAIT            = 7'd2;
    localparam [6:0] ST_FINISH          = 7'd3;
    localparam [6:0] ST_FAULT           = 7'd4;

    localparam [6:0] ST_KG_HASH_H       = 7'd10;
    localparam [6:0] ST_KG_SAMPLE_X     = 7'd11;
    localparam [6:0] ST_KG_SAMPLE_Y     = 7'd12;
    localparam [6:0] ST_KG_VECMUL       = 7'd13;
    localparam [6:0] ST_KG_PACK         = 7'd14;

    localparam [6:0] ST_EN_HASH_G       = 7'd20;
    localparam [6:0] ST_EN_SAMPLE_R1    = 7'd21;
    localparam [6:0] ST_EN_SAMPLE_R2    = 7'd22;
    localparam [6:0] ST_EN_SAMPLE_E     = 7'd23;
    localparam [6:0] ST_EN_VEC_U        = 7'd24;
    localparam [6:0] ST_EN_ENCODE       = 7'd25;
    localparam [6:0] ST_EN_VEC_V        = 7'd26;
    localparam [6:0] ST_EN_HASH_D       = 7'd27;
    localparam [6:0] ST_EN_PACK_CT      = 7'd28;
    localparam [6:0] ST_EN_HASH_K       = 7'd29;

    localparam [6:0] ST_DE_VEC_UY       = 7'd40;
    localparam [6:0] ST_DE_DECODE       = 7'd41;
    localparam [6:0] ST_DE_HASH_G       = 7'd42;
    localparam [6:0] ST_DE_SAMPLE_R1    = 7'd43;
    localparam [6:0] ST_DE_SAMPLE_R2    = 7'd44;
    localparam [6:0] ST_DE_SAMPLE_E     = 7'd45;
    localparam [6:0] ST_DE_VEC_U        = 7'd46;
    localparam [6:0] ST_DE_ENCODE       = 7'd47;
    localparam [6:0] ST_DE_VEC_V        = 7'd48;
    localparam [6:0] ST_DE_HASH_D       = 7'd49;
    localparam [6:0] ST_DE_CTCMP        = 7'd50;
    localparam [6:0] ST_DE_PACK_SS      = 7'd51;
    localparam [6:0] ST_DE_HASH_K       = 7'd52;

    localparam [6:0] ST_ZEROIZE         = 7'd60;
    localparam [6:0] ST_SELFTEST        = 7'd61;

    reg [6:0] state_q;
    reg [6:0] return_state_q;
    reg [7:0] opcode_q;
    reg [15:0] host_addr_q;
    reg [15:0] host_length_q;
    reg decap_equal_q;

    assign ready = !busy;

    task launch_primitive;
        input [7:0] id;
        input [31:0] arg;
        input [6:0] next_state;
        begin
            prim_start    <= 1'b1;
            prim_id       <= id;
            prim_arg      <= arg;
            return_state_q <= next_state;
            state_q       <= ST_WAIT;
        end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q        <= ST_IDLE;
            return_state_q <= ST_IDLE;
            opcode_q       <= 8'd0;
            host_addr_q    <= 16'd0;
            host_length_q  <= 16'd0;
            decap_equal_q  <= 1'b0;
            busy           <= 1'b0;
            done           <= 1'b0;
            err_status     <= 8'd0;
            fault_status   <= 8'd0;
            prim_start     <= 1'b0;
            prim_id        <= 8'd0;
            prim_arg       <= 32'd0;
        end else begin
            done       <= 1'b0;
            prim_start <= 1'b0;

            if (zeroize_req && (state_q == ST_IDLE)) begin
                busy          <= 1'b1;
                opcode_q      <= OPC_ZEROIZE;
                err_status    <= 8'd0;
                fault_status  <= 8'd0;
                state_q       <= ST_ZEROIZE;
            end else begin
                case (state_q)
                    ST_IDLE: begin
                        if (start) begin
                            busy          <= 1'b1;
                            opcode_q      <= opcode;
                            host_addr_q   <= host_addr;
                            host_length_q <= host_length;
                            err_status    <= 8'd0;
                            fault_status  <= 8'd0;
                            decap_equal_q <= 1'b0;
                            state_q       <= ST_DISPATCH;
                        end
                    end

                    ST_DISPATCH: begin
                        case (opcode_q)
                            OPC_KEYGEN:   state_q <= ST_KG_HASH_H;
                            OPC_ENCAP:    state_q <= ST_EN_HASH_G;
                            OPC_DECAP:    state_q <= ST_DE_VEC_UY;
                            OPC_ZEROIZE:  state_q <= ST_ZEROIZE;
                            OPC_SELFTEST: state_q <= ST_SELFTEST;
                            default: begin
                                err_status[0] <= 1'b1;
                                state_q       <= ST_FINISH;
                            end
                        endcase
                    end

                    ST_WAIT: begin
                        if (prim_fault) begin
                            fault_status[0] <= 1'b1;
                            state_q <= ST_FAULT;
                        end else if (prim_done) begin
                            if (return_state_q == ST_DE_PACK_SS) begin
                                decap_equal_q <= prim_equal;
                            end
                            state_q <= return_state_q;
                        end
                    end

                    ST_KG_HASH_H:   launch_primitive(P_HASH_H,     {8'd0, host_length_q, 8'd3}, ST_KG_SAMPLE_X);
                    ST_KG_SAMPLE_X: launch_primitive(P_SAMPLE_X,   {8'd0, 16'd66, 8'd0},        ST_KG_SAMPLE_Y);
                    ST_KG_SAMPLE_Y: launch_primitive(P_SAMPLE_Y,   {8'd0, 16'd66, 8'd1},        ST_KG_VECMUL);
                    ST_KG_VECMUL:   launch_primitive(P_VECMUL_HY,  {8'd0, host_addr_q, 8'd0},   ST_KG_PACK);
                    ST_KG_PACK:     launch_primitive(P_PACK_KEYS,  {8'd0, host_addr_q, 8'd0},   ST_FINISH);

                    ST_EN_HASH_G:    launch_primitive(P_HASH_G,     {8'd0, host_length_q, 8'd4}, ST_EN_SAMPLE_R1);
                    ST_EN_SAMPLE_R1: launch_primitive(P_SAMPLE_R1,  {8'd0, 16'd75, 8'd0},        ST_EN_SAMPLE_R2);
                    ST_EN_SAMPLE_R2: launch_primitive(P_SAMPLE_R2,  {8'd0, 16'd75, 8'd1},        ST_EN_SAMPLE_E);
                    ST_EN_SAMPLE_E:  launch_primitive(P_SAMPLE_E,   {8'd0, 16'd75, 8'd2},        ST_EN_VEC_U);
                    ST_EN_VEC_U:     launch_primitive(P_VECMUL_HR2, {8'd0, host_addr_q, 8'd0},   ST_EN_ENCODE);
                    ST_EN_ENCODE:    launch_primitive(P_ENCODE,     {8'd0, host_addr_q, 8'd0},   ST_EN_VEC_V);
                    ST_EN_VEC_V:     launch_primitive(P_VECMUL_SR2, {8'd0, host_addr_q, 8'd0},   ST_EN_HASH_D);
                    ST_EN_HASH_D:    launch_primitive(P_HASH_D,     {8'd0, host_length_q, 8'd5}, ST_EN_PACK_CT);
                    ST_EN_PACK_CT:   launch_primitive(P_PACK_CT,    {8'd0, host_addr_q, 8'd0},   ST_EN_HASH_K);
                    ST_EN_HASH_K:    launch_primitive(P_HASH_K,     {8'd0, host_length_q, 8'd5}, ST_FINISH);

                    ST_DE_VEC_UY:    launch_primitive(P_VECMUL_UY,  {8'd0, host_addr_q, 8'd0},   ST_DE_DECODE);
                    ST_DE_DECODE:    launch_primitive(P_DECODE,     {8'd0, host_addr_q, 8'd0},   ST_DE_HASH_G);
                    ST_DE_HASH_G:    launch_primitive(P_HASH_G,     {8'd0, host_length_q, 8'd4}, ST_DE_SAMPLE_R1);
                    ST_DE_SAMPLE_R1: launch_primitive(P_SAMPLE_R1,  {8'd0, 16'd75, 8'd0},        ST_DE_SAMPLE_R2);
                    ST_DE_SAMPLE_R2: launch_primitive(P_SAMPLE_R2,  {8'd0, 16'd75, 8'd1},        ST_DE_SAMPLE_E);
                    ST_DE_SAMPLE_E:  launch_primitive(P_SAMPLE_E,   {8'd0, 16'd75, 8'd2},        ST_DE_VEC_U);
                    ST_DE_VEC_U:     launch_primitive(P_VECMUL_HR2, {8'd0, host_addr_q, 8'd0},   ST_DE_ENCODE);
                    ST_DE_ENCODE:    launch_primitive(P_ENCODE,     {8'd0, host_addr_q, 8'd0},   ST_DE_VEC_V);
                    ST_DE_VEC_V:     launch_primitive(P_VECMUL_SR2, {8'd0, host_addr_q, 8'd0},   ST_DE_HASH_D);
                    ST_DE_HASH_D:    launch_primitive(P_HASH_D,     {8'd0, host_length_q, 8'd5}, ST_DE_CTCMP);
                    ST_DE_CTCMP:     launch_primitive(P_CTCMP,      {8'd0, host_addr_q, 8'd0},   ST_DE_PACK_SS);
                    ST_DE_PACK_SS: begin
                        launch_primitive(P_PACK_DECAP, {7'd0, decap_equal_q, host_addr_q, 8'd0}, ST_DE_HASH_K);
                    end
                    ST_DE_HASH_K:     launch_primitive(P_HASH_K,     {7'd0, decap_equal_q, host_length_q, 8'd5}, ST_FINISH);

                    ST_ZEROIZE:  launch_primitive(P_ZEROIZE,  32'd0, ST_FINISH);
                    ST_SELFTEST: launch_primitive(P_SELFTEST, 32'd0, ST_FINISH);

                    ST_FINISH: begin
                        busy    <= 1'b0;
                        done    <= 1'b1;
                        state_q <= ST_IDLE;
                    end

                    ST_FAULT: begin
                        busy    <= 1'b0;
                        done    <= 1'b1;
                        state_q <= ST_IDLE;
                    end

                    default: begin
                        fault_status[1] <= 1'b1;
                        state_q <= ST_FAULT;
                    end
                endcase
            end
        end
    end
endmodule
