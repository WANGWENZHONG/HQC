`timescale 1ns / 1ps
// SPI mode-0 byte slave. The system clock must be at least 4x SCLK.
module hqc_spi_slave (
    input        clk,
    input        rst_n,

    input        spi_sclk,
    input        spi_cs_n,
    input        spi_mosi,
    output reg   spi_miso,

    output reg   rx_valid,
    input        rx_ready,
    output reg [7:0] rx_data,

    input        tx_valid,
    output reg   tx_ready,
    input      [7:0] tx_data,

    output reg   err_overrun
);
    reg [2:0] sclk_sync;
    reg [2:0] cs_sync;
    reg [1:0] mosi_sync;
    reg [2:0] bit_cnt;
    reg [7:0] rx_shift;
    reg [7:0] tx_shift;

    wire cs_active = !cs_sync[2];
    wire sclk_rise = (sclk_sync[2:1] == 2'b01);
    wire sclk_fall = (sclk_sync[2:1] == 2'b10);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sclk_sync  <= 3'b000;
            cs_sync    <= 3'b111;
            mosi_sync  <= 2'b00;
            bit_cnt    <= 3'd0;
            rx_shift   <= 8'd0;
            tx_shift   <= 8'd0;
            rx_valid   <= 1'b0;
            rx_data    <= 8'd0;
            tx_ready   <= 1'b0;
            spi_miso   <= 1'b0;
            err_overrun <= 1'b0;
        end else begin
            sclk_sync <= {sclk_sync[1:0], spi_sclk};
            cs_sync   <= {cs_sync[1:0], spi_cs_n};
            mosi_sync <= {mosi_sync[0], spi_mosi};
            rx_valid  <= 1'b0;
            tx_ready  <= 1'b0;

            if (!cs_active) begin
                bit_cnt  <= 3'd0;
                tx_shift <= tx_valid ? tx_data : 8'hff;
                spi_miso <= tx_valid ? tx_data[7] : 1'b1;
            end else begin
                if (sclk_fall) begin
                    if (bit_cnt == 3'd0) begin
                        tx_ready <= 1'b1;
                        tx_shift <= tx_valid ? tx_data : 8'hff;
                        spi_miso <= tx_valid ? tx_data[7] : 1'b1;
                    end else begin
                        tx_shift <= {tx_shift[6:0], 1'b0};
                        spi_miso <= tx_shift[6];
                    end
                end

                if (sclk_rise) begin
                    rx_shift <= {rx_shift[6:0], mosi_sync[1]};
                    if (bit_cnt == 3'd7) begin
                        bit_cnt <= 3'd0;
                        if (rx_ready) begin
                            rx_data  <= {rx_shift[6:0], mosi_sync[1]};
                            rx_valid <= 1'b1;
                        end else begin
                            err_overrun <= 1'b1;
                        end
                    end else begin
                        bit_cnt <= bit_cnt + 1'b1;
                    end
                end
            end
        end
    end
endmodule
