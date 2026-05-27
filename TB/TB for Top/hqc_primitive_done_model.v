`timescale 1ns / 1ps
module hqc_primitive_done_model #(
    parameter integer LATENCY = 4
) (
    input             clk,
    input             rst_n,
    input             prim_start,
    input      [7:0]  prim_id,
    input      [31:0] prim_arg,
    output reg        prim_done,
    output reg        prim_fault,
    output reg        prim_equal
);
    reg [7:0] count_q;
    reg busy_q;
    reg [7:0] id_q;
    localparam [7:0] LATENCY_U8 = LATENCY;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            count_q    <= 8'd0;
            busy_q     <= 1'b0;
            id_q       <= 8'd0;
            prim_done  <= 1'b0;
            prim_fault <= 1'b0;
            prim_equal <= 1'b1;
        end else begin
            prim_done  <= 1'b0;
            prim_fault <= 1'b0;
            if (prim_start && !busy_q) begin
                busy_q  <= 1'b1;
                count_q <= LATENCY_U8;
                id_q    <= prim_id;
                prim_equal <= prim_arg[24] ? 1'b1 : 1'b1;
            end else if (busy_q) begin
                if (count_q == 8'd0) begin
                    busy_q    <= 1'b0;
                    prim_done <= 1'b1;
                end else begin
                    count_q <= count_q - 1'b1;
                end
            end
        end
    end

    wire unused_id = |id_q;
endmodule
