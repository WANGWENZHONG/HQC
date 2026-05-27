`timescale 1ns / 1ps
// Byte-addressed dual-port buffer used as the pk/sk/ct/ss/seed window.
module hqc_buffer_ram #(
    parameter integer ADDR_W = 16,
    parameter integer DATA_W = 8,
    parameter integer DEPTH  = 65536
) (
    input                   clk,

    input                   a_en,
    input                   a_we,
    input      [ADDR_W-1:0] a_addr,
    input      [DATA_W-1:0] a_wdata,
    output reg [DATA_W-1:0] a_rdata,

    input                   b_en,
    input                   b_we,
    input      [ADDR_W-1:0] b_addr,
    input      [DATA_W-1:0] b_wdata,
    output reg [DATA_W-1:0] b_rdata
);
    reg [DATA_W-1:0] mem [0:DEPTH-1];

    always @(posedge clk) begin
        if (a_en) begin
            if (a_we) begin
                mem[a_addr] <= a_wdata;
            end
            a_rdata <= mem[a_addr];
        end
    end

    always @(posedge clk) begin
        if (b_en) begin
            if (b_we) begin
                mem[b_addr] <= b_wdata;
            end
            b_rdata <= mem[b_addr];
        end
    end
endmodule

// Inferred 128-bit true dual-port RAM used by the supplied vector multiplier.
module vector_ram #(
    parameter integer ADDR_W = 9,
    parameter integer DATA_W = 128,
    parameter integer DEPTH  = 512
) (
    input                   clka,
    input      [ADDR_W-1:0] addra,
    input      [DATA_W-1:0] dina,
    input                   ena,
    input                   wea,

    input                   clkb,
    input      [ADDR_W-1:0] addrb,
    output reg [DATA_W-1:0] doutb,
    input                   enb
);
    reg [DATA_W-1:0] mem [0:DEPTH-1];

    always @(posedge clka) begin
        if (ena && wea) begin
            mem[addra] <= dina;
        end
    end

    always @(posedge clkb) begin
        if (enb) begin
            doutb <= mem[addrb];
        end
    end
endmodule
