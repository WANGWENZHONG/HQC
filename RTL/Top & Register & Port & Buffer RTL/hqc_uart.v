`timescale 1ns / 1ps

module hqc_uart_rx #(
    parameter integer CLKS_PER_BIT = 868
) (
    input        clk,
    input        rst_n,
    input        uart_rx,
    output reg [7:0] data,
    output reg       valid,
    output reg       framing_error
);
    localparam [2:0] ST_IDLE  = 3'd0;
    localparam [2:0] ST_START = 3'd1;
    localparam [2:0] ST_DATA  = 3'd2;
    localparam [2:0] ST_STOP  = 3'd3;

    reg [2:0] state_q;
    reg [15:0] clk_cnt;
    reg [2:0] bit_idx;
    reg [1:0] rx_sync;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q       <= ST_IDLE;
            clk_cnt       <= 16'd0;
            bit_idx       <= 3'd0;
            rx_sync       <= 2'b11;
            data          <= 8'd0;
            valid         <= 1'b0;
            framing_error <= 1'b0;
        end else begin
            rx_sync <= {rx_sync[0], uart_rx};
            valid   <= 1'b0;

            case (state_q)
                ST_IDLE: begin
                    clk_cnt <= 16'd0;
                    bit_idx <= 3'd0;
                    if (!rx_sync[1]) begin
                        state_q <= ST_START;
                    end
                end
                ST_START: begin
                    if (clk_cnt == (CLKS_PER_BIT/2)) begin
                        if (!rx_sync[1]) begin
                            clk_cnt <= 16'd0;
                            state_q <= ST_DATA;
                        end else begin
                            state_q <= ST_IDLE;
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end
                ST_DATA: begin
                    if (clk_cnt == CLKS_PER_BIT-1) begin
                        clk_cnt <= 16'd0;
                        data[bit_idx] <= rx_sync[1];
                        if (bit_idx == 3'd7) begin
                            bit_idx <= 3'd0;
                            state_q <= ST_STOP;
                        end else begin
                            bit_idx <= bit_idx + 1'b1;
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end
                ST_STOP: begin
                    if (clk_cnt == CLKS_PER_BIT-1) begin
                        valid <= rx_sync[1];
                        framing_error <= !rx_sync[1];
                        state_q <= ST_IDLE;
                        clk_cnt <= 16'd0;
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end
                default: state_q <= ST_IDLE;
            endcase
        end
    end
endmodule

module hqc_uart_tx #(
    parameter integer CLKS_PER_BIT = 868
) (
    input        clk,
    input        rst_n,
    input        valid,
    output       ready,
    input  [7:0] data,
    output reg   uart_tx,
    output reg   busy
);
    localparam [2:0] ST_IDLE  = 3'd0;
    localparam [2:0] ST_START = 3'd1;
    localparam [2:0] ST_DATA  = 3'd2;
    localparam [2:0] ST_STOP  = 3'd3;

    reg [2:0] state_q;
    reg [15:0] clk_cnt;
    reg [2:0] bit_idx;
    reg [7:0] data_q;

    assign ready = (state_q == ST_IDLE);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q <= ST_IDLE;
            clk_cnt <= 16'd0;
            bit_idx <= 3'd0;
            data_q  <= 8'd0;
            uart_tx <= 1'b1;
            busy    <= 1'b0;
        end else begin
            case (state_q)
                ST_IDLE: begin
                    uart_tx <= 1'b1;
                    busy    <= 1'b0;
                    clk_cnt <= 16'd0;
                    bit_idx <= 3'd0;
                    if (valid) begin
                        data_q  <= data;
                        state_q <= ST_START;
                        busy    <= 1'b1;
                    end
                end
                ST_START: begin
                    uart_tx <= 1'b0;
                    if (clk_cnt == CLKS_PER_BIT-1) begin
                        clk_cnt <= 16'd0;
                        state_q <= ST_DATA;
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end
                ST_DATA: begin
                    uart_tx <= data_q[bit_idx];
                    if (clk_cnt == CLKS_PER_BIT-1) begin
                        clk_cnt <= 16'd0;
                        if (bit_idx == 3'd7) begin
                            bit_idx <= 3'd0;
                            state_q <= ST_STOP;
                        end else begin
                            bit_idx <= bit_idx + 1'b1;
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end
                ST_STOP: begin
                    uart_tx <= 1'b1;
                    if (clk_cnt == CLKS_PER_BIT-1) begin
                        clk_cnt <= 16'd0;
                        state_q <= ST_IDLE;
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end
                default: state_q <= ST_IDLE;
            endcase
        end
    end
endmodule
