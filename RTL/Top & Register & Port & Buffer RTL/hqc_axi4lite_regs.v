`timescale 1ns / 1ps
// Minimal AXI4-Lite register file for PS-side control.
module hqc_axi4lite_regs #(
    parameter integer AXI_ADDR_W = 12
) (
    input                       clk,
    input                       rst_n,

    input      [AXI_ADDR_W-1:0] s_axi_awaddr,
    input                       s_axi_awvalid,
    output reg                  s_axi_awready,
    input      [31:0]           s_axi_wdata,
    input      [3:0]            s_axi_wstrb,
    input                       s_axi_wvalid,
    output reg                  s_axi_wready,
    output reg [1:0]            s_axi_bresp,
    output reg                  s_axi_bvalid,
    input                       s_axi_bready,

    input      [AXI_ADDR_W-1:0] s_axi_araddr,
    input                       s_axi_arvalid,
    output reg                  s_axi_arready,
    output reg [31:0]           s_axi_rdata,
    output reg [1:0]            s_axi_rresp,
    output reg                  s_axi_rvalid,
    input                       s_axi_rready,

    output reg                  cmd_start,
    output reg [7:0]            cmd_opcode,
    output reg [15:0]           cmd_length,
    output reg [15:0]           cmd_addr,
    output reg                  zeroize_req,
    output     [255:0]          seed_words,

    input                       kem_busy,
    input                       kem_done,
    input      [7:0]            err_status,
    input      [7:0]            fault_status,
    output                      irq
);
    localparam [7:0] REG_CMD       = 8'h00;
    localparam [7:0] REG_STATUS    = 8'h04;
    localparam [7:0] REG_IRQ_EN    = 8'h08;
    localparam [7:0] REG_LEN       = 8'h0c;
    localparam [7:0] REG_ADDR      = 8'h10;
    localparam [7:0] REG_ERR       = 8'h14;
    localparam [7:0] REG_FAULT     = 8'h18;
    localparam [7:0] REG_ZEROIZE   = 8'h1c;
    localparam [7:0] REG_SEED0     = 8'h20;

    reg [31:0] seed_reg [0:7];
    reg [31:0] irq_enable;
    reg        done_latch;

    reg [AXI_ADDR_W-1:0] awaddr_q;
    reg [31:0]           wdata_q;
    reg [3:0]            wstrb_q;
    reg                  aw_hold;
    reg                  w_hold;

    wire write_fire = aw_hold && w_hold && !s_axi_bvalid;
    wire [7:0] wr_addr = awaddr_q[7:0];
    wire [7:0] rd_addr = s_axi_araddr[7:0];

    assign irq = irq_enable[0] & (done_latch | (|err_status) | (|fault_status));
    assign seed_words = {seed_reg[7], seed_reg[6], seed_reg[5], seed_reg[4],
                         seed_reg[3], seed_reg[2], seed_reg[1], seed_reg[0]};

    function [31:0] apply_wstrb;
        input [31:0] old_value;
        input [31:0] new_value;
        input [3:0]  strobe;
        begin
            apply_wstrb[7:0]   = strobe[0] ? new_value[7:0]   : old_value[7:0];
            apply_wstrb[15:8]  = strobe[1] ? new_value[15:8]  : old_value[15:8];
            apply_wstrb[23:16] = strobe[2] ? new_value[23:16] : old_value[23:16];
            apply_wstrb[31:24] = strobe[3] ? new_value[31:24] : old_value[31:24];
        end
    endfunction

    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axi_awready <= 1'b0;
            s_axi_wready  <= 1'b0;
            s_axi_bresp   <= 2'b00;
            s_axi_bvalid  <= 1'b0;
            s_axi_arready <= 1'b0;
            s_axi_rdata   <= 32'd0;
            s_axi_rresp   <= 2'b00;
            s_axi_rvalid  <= 1'b0;
            awaddr_q      <= {AXI_ADDR_W{1'b0}};
            wdata_q       <= 32'd0;
            wstrb_q       <= 4'd0;
            aw_hold       <= 1'b0;
            w_hold        <= 1'b0;
            cmd_start     <= 1'b0;
            cmd_opcode    <= 8'd0;
            cmd_length    <= 16'd0;
            cmd_addr      <= 16'd0;
            zeroize_req   <= 1'b0;
            irq_enable    <= 32'd0;
            done_latch    <= 1'b0;
            for (i = 0; i < 8; i = i + 1) begin
                seed_reg[i] <= 32'd0;
            end
        end else begin
            cmd_start   <= 1'b0;
            zeroize_req <= 1'b0;
            done_latch  <= done_latch | kem_done;

            s_axi_awready <= !aw_hold && !s_axi_bvalid;
            s_axi_wready  <= !w_hold && !s_axi_bvalid;
            s_axi_arready <= !s_axi_rvalid;

            if (s_axi_awvalid && s_axi_awready) begin
                awaddr_q <= s_axi_awaddr;
                aw_hold  <= 1'b1;
            end

            if (s_axi_wvalid && s_axi_wready) begin
                wdata_q <= s_axi_wdata;
                wstrb_q <= s_axi_wstrb;
                w_hold  <= 1'b1;
            end

            if (write_fire) begin
                s_axi_bvalid <= 1'b1;
                s_axi_bresp  <= 2'b00;
                aw_hold      <= 1'b0;
                w_hold       <= 1'b0;

                case (wr_addr)
                    REG_CMD: begin
                        if (wdata_q[0]) begin
                            cmd_start  <= 1'b1;
                            cmd_opcode <= wdata_q[15:8];
                        end
                    end
                    REG_STATUS: begin
                        if (wdata_q[0]) begin
                            done_latch <= 1'b0;
                        end
                    end
                    REG_IRQ_EN: begin
                        irq_enable <= apply_wstrb(irq_enable, wdata_q, wstrb_q);
                    end
                    REG_LEN: begin
                        cmd_length <= apply_wstrb({16'd0, cmd_length}, wdata_q, wstrb_q);
                    end
                    REG_ADDR: begin
                        cmd_addr <= apply_wstrb({16'd0, cmd_addr}, wdata_q, wstrb_q);
                    end
                    REG_ZEROIZE: begin
                        if (wdata_q[0]) begin
                            zeroize_req <= 1'b1;
                        end
                    end
                    REG_SEED0: seed_reg[0] <= apply_wstrb(seed_reg[0], wdata_q, wstrb_q);
                    8'h24:    seed_reg[1] <= apply_wstrb(seed_reg[1], wdata_q, wstrb_q);
                    8'h28:    seed_reg[2] <= apply_wstrb(seed_reg[2], wdata_q, wstrb_q);
                    8'h2c:    seed_reg[3] <= apply_wstrb(seed_reg[3], wdata_q, wstrb_q);
                    8'h30:    seed_reg[4] <= apply_wstrb(seed_reg[4], wdata_q, wstrb_q);
                    8'h34:    seed_reg[5] <= apply_wstrb(seed_reg[5], wdata_q, wstrb_q);
                    8'h38:    seed_reg[6] <= apply_wstrb(seed_reg[6], wdata_q, wstrb_q);
                    8'h3c:    seed_reg[7] <= apply_wstrb(seed_reg[7], wdata_q, wstrb_q);
                    default: begin
                    end
                endcase
            end else if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid <= 1'b0;
            end

            if (s_axi_arvalid && s_axi_arready) begin
                s_axi_rvalid <= 1'b1;
                s_axi_rresp  <= 2'b00;
                case (rd_addr)
                    REG_CMD:     s_axi_rdata <= {16'd0, cmd_opcode, 7'd0, kem_busy};
                    REG_STATUS:  s_axi_rdata <= {27'd0, irq, |fault_status, |err_status, kem_busy, done_latch};
                    REG_IRQ_EN:  s_axi_rdata <= irq_enable;
                    REG_LEN:     s_axi_rdata <= {16'd0, cmd_length};
                    REG_ADDR:    s_axi_rdata <= {16'd0, cmd_addr};
                    REG_ERR:     s_axi_rdata <= {24'd0, err_status};
                    REG_FAULT:   s_axi_rdata <= {24'd0, fault_status};
                    REG_SEED0:   s_axi_rdata <= seed_reg[0];
                    8'h24:       s_axi_rdata <= seed_reg[1];
                    8'h28:       s_axi_rdata <= seed_reg[2];
                    8'h2c:       s_axi_rdata <= seed_reg[3];
                    8'h30:       s_axi_rdata <= seed_reg[4];
                    8'h34:       s_axi_rdata <= seed_reg[5];
                    8'h38:       s_axi_rdata <= seed_reg[6];
                    8'h3c:       s_axi_rdata <= seed_reg[7];
                    default:     s_axi_rdata <= 32'd0;
                endcase
            end else if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid <= 1'b0;
            end
        end
    end
endmodule
