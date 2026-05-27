`timescale 1ns / 1ps
// Platform top for the HQC-128 accelerator control plane.
module hqc_accel_top #(
    parameter integer UART_CLKS_PER_BIT = 868
) (
    input             clk,
    input             rst_n,

    input             spi_sclk,
    input             spi_cs_n,
    input             spi_mosi,
    output            spi_miso,

    input             uart_rx,
    output            uart_tx,

    input      [11:0] s_axi_awaddr,
    input             s_axi_awvalid,
    output            s_axi_awready,
    input      [31:0] s_axi_wdata,
    input      [3:0]  s_axi_wstrb,
    input             s_axi_wvalid,
    output            s_axi_wready,
    output     [1:0]  s_axi_bresp,
    output            s_axi_bvalid,
    input             s_axi_bready,
    input      [11:0] s_axi_araddr,
    input             s_axi_arvalid,
    output            s_axi_arready,
    output     [31:0] s_axi_rdata,
    output     [1:0]  s_axi_rresp,
    output            s_axi_rvalid,
    input             s_axi_rready,

    output            irq,

    output            prim_start,
    output     [7:0]  prim_id,
    output     [31:0] prim_arg,
    input             prim_done,
    input             prim_fault,
    input             prim_equal
);
    localparam [7:0] OPC_READ_MEM  = 8'h11;
    localparam [7:0] OPC_WRITE_MEM = 8'h10;

    wire        spi_rx_valid;
    wire        spi_rx_ready;
    wire [7:0]  spi_rx_data;
    wire        spi_tx_valid;
    wire        spi_tx_ready;
    wire [7:0]  spi_tx_data;
    wire        spi_overrun;

    hqc_spi_slave u_spi (
        .clk         (clk),
        .rst_n       (rst_n),
        .spi_sclk    (spi_sclk),
        .spi_cs_n    (spi_cs_n),
        .spi_mosi    (spi_mosi),
        .spi_miso    (spi_miso),
        .rx_valid    (spi_rx_valid),
        .rx_ready    (spi_rx_ready),
        .rx_data     (spi_rx_data),
        .tx_valid    (spi_tx_valid),
        .tx_ready    (spi_tx_ready),
        .tx_data     (spi_tx_data),
        .err_overrun (spi_overrun)
    );

    wire [7:0] uart_rx_data;
    wire       uart_rx_valid;
    wire       uart_frame_err;
    wire       uart_tx_valid;
    wire       uart_tx_ready;
    wire [7:0] uart_tx_data;
    wire       uart_tx_busy;

    hqc_uart_rx #(
        .CLKS_PER_BIT(UART_CLKS_PER_BIT)
    ) u_uart_rx (
        .clk           (clk),
        .rst_n         (rst_n),
        .uart_rx       (uart_rx),
        .data          (uart_rx_data),
        .valid         (uart_rx_valid),
        .framing_error (uart_frame_err)
    );

    hqc_uart_tx #(
        .CLKS_PER_BIT(UART_CLKS_PER_BIT)
    ) u_uart_tx (
        .clk     (clk),
        .rst_n   (rst_n),
        .valid   (uart_tx_valid),
        .ready   (uart_tx_ready),
        .data    (uart_tx_data),
        .uart_tx (uart_tx),
        .busy    (uart_tx_busy)
    );

    wire        rx_fifo_full;
    wire        rx_fifo_empty;
    wire [8:0]  rx_fifo_rdata;
    reg         rx_fifo_rd_en;
    wire        rx_fifo_wr_en = (spi_rx_valid && !rx_fifo_full) ||
                                (!spi_rx_valid && uart_rx_valid && !rx_fifo_full);
    wire [8:0]  rx_fifo_wdata = spi_rx_valid ? {1'b0, spi_rx_data} : {1'b1, uart_rx_data};
    assign spi_rx_ready = !rx_fifo_full;

    hqc_sync_fifo #(
        .DATA_W(9),
        .ADDR_W(8),
        .DEPTH(256)
    ) u_rx_fifo (
        .clk     (clk),
        .rst_n   (rst_n),
        .clear   (1'b0),
        .wr_en   (rx_fifo_wr_en),
        .wr_data (rx_fifo_wdata),
        .full    (rx_fifo_full),
        .rd_en   (rx_fifo_rd_en),
        .rd_data (rx_fifo_rdata),
        .empty   (rx_fifo_empty),
        .level   ()
    );

    reg rx_hold_valid;
    reg rx_pop_d;
    reg [7:0] rx_hold_data;
    reg       rx_hold_uart;
    wire cmd_byte_ready;
    wire cmd_byte_valid = rx_hold_valid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_fifo_rd_en <= 1'b0;
            rx_pop_d      <= 1'b0;
            rx_hold_valid <= 1'b0;
            rx_hold_data  <= 8'd0;
            rx_hold_uart  <= 1'b0;
        end else begin
            rx_fifo_rd_en <= 1'b0;
            rx_pop_d      <= rx_fifo_rd_en;

            if (rx_pop_d) begin
                rx_hold_valid <= 1'b1;
                rx_hold_data  <= rx_fifo_rdata[7:0];
                rx_hold_uart  <= rx_fifo_rdata[8];
            end else if (rx_hold_valid && cmd_byte_ready) begin
                rx_hold_valid <= 1'b0;
            end

            if (!rx_hold_valid && !rx_pop_d && !rx_fifo_empty) begin
                rx_fifo_rd_en <= 1'b1;
            end
        end
    end

    wire        frame_cmd_valid;
    wire        frame_cmd_ready;
    wire [7:0]  frame_opcode;
    wire [7:0]  frame_flags;
    wire [15:0] frame_length;
    wire [15:0] frame_addr;
    wire        frame_mem_we;
    wire [15:0] frame_mem_addr;
    wire [7:0]  frame_mem_wdata;
    wire        frame_bad_crc;
    wire        frame_bad_len;
    wire        frame_unexpected;

    hqc_cmd_frame_rx u_frame_rx (
        .clk            (clk),
        .rst_n          (rst_n),
        .byte_valid     (cmd_byte_valid),
        .byte_ready     (cmd_byte_ready),
        .byte_data      (rx_hold_data),
        .cmd_valid      (frame_cmd_valid),
        .cmd_ready      (frame_cmd_ready),
        .cmd_opcode     (frame_opcode),
        .cmd_flags      (frame_flags),
        .cmd_length     (frame_length),
        .cmd_addr       (frame_addr),
        .mem_wr_en      (frame_mem_we),
        .mem_wr_addr    (frame_mem_addr),
        .mem_wr_data    (frame_mem_wdata),
        .err_bad_crc    (frame_bad_crc),
        .err_bad_len    (frame_bad_len),
        .err_unexpected (frame_unexpected)
    );

    wire        resp_mem_rd_en;
    wire [15:0] resp_mem_rd_addr;
    wire [7:0]  resp_mem_rd_data;

    hqc_buffer_ram u_buffer_ram (
        .clk     (clk),
        .a_en    (frame_mem_we),
        .a_we    (frame_mem_we),
        .a_addr  (frame_mem_addr),
        .a_wdata (frame_mem_wdata),
        .a_rdata (),
        .b_en    (resp_mem_rd_en),
        .b_we    (1'b0),
        .b_addr  (resp_mem_rd_addr),
        .b_wdata (8'd0),
        .b_rdata (resp_mem_rd_data)
    );

    wire        axi_cmd_start;
    wire [7:0]  axi_opcode;
    wire [15:0] axi_length;
    wire [15:0] axi_addr;
    wire        axi_zeroize;
    wire [255:0] seed_words;

    wire kem_ready;
    wire kem_busy;
    wire kem_done;
    wire [7:0] kem_err_status;
    wire [7:0] kem_fault_status;

    hqc_axi4lite_regs u_regs (
        .clk           (clk),
        .rst_n         (rst_n),
        .s_axi_awaddr  (s_axi_awaddr),
        .s_axi_awvalid (s_axi_awvalid),
        .s_axi_awready (s_axi_awready),
        .s_axi_wdata   (s_axi_wdata),
        .s_axi_wstrb   (s_axi_wstrb),
        .s_axi_wvalid  (s_axi_wvalid),
        .s_axi_wready  (s_axi_wready),
        .s_axi_bresp   (s_axi_bresp),
        .s_axi_bvalid  (s_axi_bvalid),
        .s_axi_bready  (s_axi_bready),
        .s_axi_araddr  (s_axi_araddr),
        .s_axi_arvalid (s_axi_arvalid),
        .s_axi_arready (s_axi_arready),
        .s_axi_rdata   (s_axi_rdata),
        .s_axi_rresp   (s_axi_rresp),
        .s_axi_rvalid  (s_axi_rvalid),
        .s_axi_rready  (s_axi_rready),
        .cmd_start     (axi_cmd_start),
        .cmd_opcode    (axi_opcode),
        .cmd_length    (axi_length),
        .cmd_addr      (axi_addr),
        .zeroize_req   (axi_zeroize),
        .seed_words    (seed_words),
        .kem_busy      (kem_busy),
        .kem_done      (kem_done),
        .err_status    (kem_err_status),
        .fault_status  (kem_fault_status),
        .irq           (irq)
    );

    reg        kem_start_q;
    reg [7:0]  kem_opcode_q;
    reg [15:0] kem_addr_q;
    reg [15:0] kem_length_q;

    hqc_kem_scheduler u_scheduler (
        .clk          (clk),
        .rst_n        (rst_n),
        .start        (kem_start_q),
        .opcode       (kem_opcode_q),
        .host_addr    (kem_addr_q),
        .host_length  (kem_length_q),
        .zeroize_req  (axi_zeroize),
        .ready        (kem_ready),
        .busy         (kem_busy),
        .done         (kem_done),
        .err_status   (kem_err_status),
        .fault_status (kem_fault_status),
        .prim_start   (prim_start),
        .prim_id      (prim_id),
        .prim_arg     (prim_arg),
        .prim_done    (prim_done),
        .prim_fault   (prim_fault),
        .prim_equal   (prim_equal)
    );

    wire        tx_fifo_full;
    wire        tx_fifo_empty;
    wire [7:0]  tx_fifo_rdata;
    reg         tx_fifo_rd_en;
    wire        uart_fifo_full;
    wire        uart_fifo_empty;
    wire [7:0]  uart_fifo_rdata;
    reg         uart_fifo_rd_en;
    wire        resp_out_valid;
    reg         resp_uart_route_q;
    wire        resp_out_ready = !tx_fifo_full && (!resp_uart_route_q || !uart_fifo_full);
    wire [7:0]  resp_out_data;
    wire        tx_fifo_wr_en = resp_out_valid && resp_out_ready;
    wire        uart_fifo_wr_en = resp_uart_route_q && resp_out_valid && resp_out_ready;

    hqc_sync_fifo #(
        .DATA_W(8),
        .ADDR_W(8),
        .DEPTH(256)
    ) u_tx_fifo (
        .clk     (clk),
        .rst_n   (rst_n),
        .clear   (1'b0),
        .wr_en   (tx_fifo_wr_en),
        .wr_data (resp_out_data),
        .full    (tx_fifo_full),
        .rd_en   (tx_fifo_rd_en),
        .rd_data (tx_fifo_rdata),
        .empty   (tx_fifo_empty),
        .level   ()
    );

    hqc_sync_fifo #(
        .DATA_W(8),
        .ADDR_W(8),
        .DEPTH(256)
    ) u_uart_tx_fifo (
        .clk     (clk),
        .rst_n   (rst_n),
        .clear   (1'b0),
        .wr_en   (uart_fifo_wr_en),
        .wr_data (resp_out_data),
        .full    (uart_fifo_full),
        .rd_en   (uart_fifo_rd_en),
        .rd_data (uart_fifo_rdata),
        .empty   (uart_fifo_empty),
        .level   ()
    );

    reg tx_hold_valid;
    reg tx_pop_d;
    reg [7:0] tx_hold_data;
    assign spi_tx_valid = tx_hold_valid;
    assign spi_tx_data  = tx_hold_data;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_fifo_rd_en <= 1'b0;
            tx_pop_d      <= 1'b0;
            tx_hold_valid <= 1'b0;
            tx_hold_data  <= 8'hff;
        end else begin
            tx_fifo_rd_en <= 1'b0;
            tx_pop_d      <= tx_fifo_rd_en;

            if (tx_pop_d) begin
                tx_hold_valid <= 1'b1;
                tx_hold_data  <= tx_fifo_rdata;
            end else if (tx_hold_valid && spi_tx_ready) begin
                tx_hold_valid <= 1'b0;
            end

            if (!tx_hold_valid && !tx_pop_d && !tx_fifo_empty) begin
                tx_fifo_rd_en <= 1'b1;
            end
        end
    end

    reg uart_hold_valid;
    reg uart_pop_d;
    reg [7:0] uart_hold_data;
    assign uart_tx_valid = uart_hold_valid;
    assign uart_tx_data  = uart_hold_data;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            uart_fifo_rd_en <= 1'b0;
            uart_pop_d      <= 1'b0;
            uart_hold_valid <= 1'b0;
            uart_hold_data  <= 8'hff;
        end else begin
            uart_fifo_rd_en <= 1'b0;
            uart_pop_d      <= uart_fifo_rd_en;

            if (uart_pop_d) begin
                uart_hold_valid <= 1'b1;
                uart_hold_data  <= uart_fifo_rdata;
            end else if (uart_hold_valid && uart_tx_ready) begin
                uart_hold_valid <= 1'b0;
            end

            if (!uart_hold_valid && !uart_pop_d && !uart_fifo_empty) begin
                uart_fifo_rd_en <= 1'b1;
            end
        end
    end

    reg        resp_start_q;
    reg [7:0]  resp_opcode_q;
    reg [7:0]  resp_status_q;
    reg [15:0] resp_length_q;
    reg [15:0] resp_addr_q;
    wire       resp_busy;
    wire       resp_done;

    hqc_resp_frame_tx u_resp_tx (
        .clk         (clk),
        .rst_n       (rst_n),
        .start       (resp_start_q),
        .busy        (resp_busy),
        .done        (resp_done),
        .opcode      (resp_opcode_q),
        .status      (resp_status_q),
        .length      (resp_length_q),
        .base_addr   (resp_addr_q),
        .mem_rd_en   (resp_mem_rd_en),
        .mem_rd_addr (resp_mem_rd_addr),
        .mem_rd_data (resp_mem_rd_data),
        .out_valid   (resp_out_valid),
        .out_ready   (resp_out_ready),
        .out_data    (resp_out_data)
    );

    reg        pending_resp_q;
    reg [7:0]  pending_opcode_q;
    reg [7:0]  pending_status_q;
    reg [15:0] pending_length_q;
    reg [15:0] pending_addr_q;
    reg        pending_uart_q;
    reg [7:0]  last_opcode_q;
    reg        last_uart_route_q;

    assign frame_cmd_ready = kem_ready && !pending_resp_q && !resp_busy;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            kem_start_q      <= 1'b0;
            kem_opcode_q     <= 8'd0;
            kem_addr_q       <= 16'd0;
            kem_length_q     <= 16'd0;
            resp_start_q     <= 1'b0;
            resp_opcode_q    <= 8'd0;
            resp_status_q    <= 8'd0;
            resp_length_q    <= 16'd0;
            resp_addr_q      <= 16'd0;
            pending_resp_q   <= 1'b0;
            pending_opcode_q <= 8'd0;
            pending_status_q <= 8'd0;
            pending_length_q <= 16'd0;
            pending_addr_q   <= 16'd0;
            pending_uart_q   <= 1'b0;
            last_opcode_q    <= 8'd0;
            last_uart_route_q <= 1'b0;
            resp_uart_route_q <= 1'b0;
        end else begin
            kem_start_q  <= 1'b0;
            resp_start_q <= 1'b0;

            if ((frame_bad_crc || frame_bad_len || frame_unexpected) && !pending_resp_q) begin
                pending_resp_q   <= 1'b1;
                pending_opcode_q <= 8'hfe;
                pending_status_q <= {5'd0, frame_unexpected, frame_bad_len, frame_bad_crc};
                pending_length_q <= 16'd0;
                pending_addr_q   <= 16'd0;
                pending_uart_q   <= rx_hold_uart;
            end

            if (axi_cmd_start && kem_ready) begin
                kem_start_q  <= 1'b1;
                kem_opcode_q <= axi_opcode;
                kem_addr_q   <= axi_addr;
                kem_length_q <= axi_length;
                last_opcode_q <= axi_opcode;
                last_uart_route_q <= 1'b0;
            end else if (frame_cmd_valid && frame_cmd_ready) begin
                last_opcode_q <= frame_opcode;
                last_uart_route_q <= frame_flags[7] | rx_hold_uart;
                if (frame_opcode == OPC_READ_MEM) begin
                    pending_resp_q   <= 1'b1;
                    pending_opcode_q <= frame_opcode;
                    pending_status_q <= 8'd0;
                    pending_length_q <= frame_length;
                    pending_addr_q   <= frame_addr;
                    pending_uart_q   <= frame_flags[7] | rx_hold_uart;
                end else if (frame_opcode == OPC_WRITE_MEM) begin
                    pending_resp_q   <= 1'b1;
                    pending_opcode_q <= frame_opcode;
                    pending_status_q <= 8'd0;
                    pending_length_q <= 16'd0;
                    pending_addr_q   <= frame_addr;
                    pending_uart_q   <= frame_flags[7] | rx_hold_uart;
                end else begin
                    kem_start_q  <= 1'b1;
                    kem_opcode_q <= frame_opcode;
                    kem_addr_q   <= frame_addr;
                    kem_length_q <= frame_length;
                end
            end

            if (kem_done && !pending_resp_q) begin
                pending_resp_q   <= 1'b1;
                pending_opcode_q <= last_opcode_q;
                pending_status_q <= {|kem_fault_status, |kem_err_status, 6'd0};
                pending_length_q <= 16'd0;
                pending_addr_q   <= 16'd0;
                pending_uart_q   <= last_uart_route_q;
            end

            if (pending_resp_q && !resp_busy) begin
                resp_start_q     <= 1'b1;
                resp_opcode_q    <= pending_opcode_q;
                resp_status_q    <= pending_status_q;
                resp_length_q    <= pending_length_q;
                resp_addr_q      <= pending_addr_q;
                resp_uart_route_q <= pending_uart_q;
                pending_resp_q   <= 1'b0;
            end
        end
    end

    wire unused_spi_overrun = spi_overrun;
    wire unused_uart_frame_err = uart_frame_err;
    wire unused_uart_tx_busy = uart_tx_busy;
    wire unused_resp_done = resp_done;
    wire unused_seed = |seed_words;
endmodule
