`timescale 1ns / 1ps

module hqc_consttime_compare #(
    parameter integer LEN_W = 16
) (
    input              clk,
    input              rst_n,
    input              start,
    input  [LEN_W-1:0] length,
    input              valid,
    input      [7:0]   a_byte,
    input      [7:0]   b_byte,
    output             ready,
    output reg         busy,
    output reg         done,
    output reg         equal
);
    reg [LEN_W-1:0] remaining;
    reg [7:0] diff_acc;

    assign ready = busy;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy      <= 1'b0;
            done      <= 1'b0;
            equal     <= 1'b0;
            remaining <= {LEN_W{1'b0}};
            diff_acc  <= 8'h00;
        end else begin
            done <= 1'b0;

            if (start && !busy) begin
                busy      <= 1'b1;
                remaining <= length;
                diff_acc  <= 8'h00;
                equal     <= 1'b0;
                if (length == {LEN_W{1'b0}}) begin
                    busy  <= 1'b0;
                    done  <= 1'b1;
                    equal <= 1'b1;
                end
            end else if (busy && valid) begin
                diff_acc  <= diff_acc | (a_byte ^ b_byte);
                remaining <= remaining - 1'b1;
                if (remaining == {{(LEN_W-1){1'b0}}, 1'b1}) begin
                    busy  <= 1'b0;
                    done  <= 1'b1;
                    equal <= ((diff_acc | (a_byte ^ b_byte)) == 8'h00);
                end
            end
        end
    end
endmodule

module hqc_secure_select_byte (
    input      [7:0] true_byte,
    input      [7:0] false_byte,
    input            select_true,
    output     [7:0] out_byte
);
    wire [7:0] mask = {8{select_true}};
    assign out_byte = (true_byte & mask) | (false_byte & ~mask);
endmodule

module hqc_watchdog #(
    parameter integer COUNT_W = 24,
    parameter [COUNT_W-1:0] LIMIT = 24'd1000000
) (
    input  clk,
    input  rst_n,
    input  enable,
    input  clear,
    output reg fault
);
    reg [COUNT_W-1:0] count_q;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            count_q <= {COUNT_W{1'b0}};
            fault   <= 1'b0;
        end else if (clear) begin
            count_q <= {COUNT_W{1'b0}};
            fault   <= 1'b0;
        end else if (enable && !fault) begin
            if (count_q == LIMIT) begin
                fault <= 1'b1;
            end else begin
                count_q <= count_q + 1'b1;
            end
        end
    end
endmodule

module hqc_fault_latch (
    input        clk,
    input        rst_n,
    input        clear,
    input  [7:0] fault_set,
    output reg [7:0] fault_status,
    output       any_fault
);
    assign any_fault = |fault_status;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fault_status <= 8'h00;
        end else if (clear) begin
            fault_status <= 8'h00;
        end else begin
            fault_status <= fault_status | fault_set;
        end
    end
endmodule
