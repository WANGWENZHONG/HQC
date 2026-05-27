`timescale 1ns / 1ps
// Small synchronous FIFO for command and byte streams.
module hqc_sync_fifo #(
    parameter integer DATA_W = 8,
    parameter integer ADDR_W = 4,
    parameter integer DEPTH  = 16
) (
    input                   clk,
    input                   rst_n,
    input                   clear,

    input                   wr_en,
    input      [DATA_W-1:0] wr_data,
    output                  full,

    input                   rd_en,
    output reg [DATA_W-1:0] rd_data,
    output                  empty,

    output reg [ADDR_W:0]   level
);
    reg [DATA_W-1:0] mem [0:DEPTH-1];
    reg [ADDR_W-1:0] wr_ptr;
    reg [ADDR_W-1:0] rd_ptr;
    localparam [ADDR_W:0] DEPTH_U = DEPTH;

    wire do_wr = wr_en && !full;
    wire do_rd = rd_en && !empty;

    assign full  = (level == DEPTH_U);
    assign empty = (level == {(ADDR_W+1){1'b0}});

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr  <= {ADDR_W{1'b0}};
            rd_ptr  <= {ADDR_W{1'b0}};
            rd_data <= {DATA_W{1'b0}};
            level   <= {(ADDR_W+1){1'b0}};
        end else if (clear) begin
            wr_ptr  <= {ADDR_W{1'b0}};
            rd_ptr  <= {ADDR_W{1'b0}};
            rd_data <= {DATA_W{1'b0}};
            level   <= {(ADDR_W+1){1'b0}};
        end else begin
            if (do_wr) begin
                mem[wr_ptr] <= wr_data;
                wr_ptr <= wr_ptr + 1'b1;
            end

            if (do_rd) begin
                rd_data <= mem[rd_ptr];
                rd_ptr <= rd_ptr + 1'b1;
            end

            case ({do_wr, do_rd})
                2'b10: level <= level + 1'b1;
                2'b01: level <= level - 1'b1;
                default: level <= level;
            endcase
        end
    end
endmodule
