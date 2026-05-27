`timescale 1ns / 1ps
module gf_mul_pipline_4 (
    input                           clk,
    input                           rst_n,
    input                           start,
    input               [7:0]       in_1,
    input               [7:0]       in_2,
    output      reg     [7:0]       out,
    output      reg                 done
);

// ------------------------------------------------------------------
//  每级做2步蝶形运算
//  原8级：bit7→bit6→bit5→bit4→bit3→bit2→bit1→bit0
//  合并4级：
//    Stage1：bit7, bit6
//    Stage2：bit5, bit4
//    Stage3：bit3, bit2
//    Stage4：bit1, bit0 → 输出
// ------------------------------------------------------------------

// 辅助函数：GF移位（乘以alpha，即左移一位后模归约）
// step[7]为1时 XOR 0x1D，否则直接左移
// 用wire内联实现，综合器会优化

// 级间寄存器
reg [7:0] step_1_reg;
reg [7:0] step_2_reg;
reg [7:0] step_3_reg;

// in_2 透传寄存器（每级需要用到对应的bit）
reg [7:0] store_1;
reg [7:0] store_2;
reg [7:0] store_3;

// 有效信号流水
reg ca_vld_1;
reg ca_vld_2;
reg ca_vld_3;

// in_1 透传寄存器（每级都要用到 in_1）
reg [7:0] in1_s1;
reg [7:0] in1_s2;
reg [7:0] in1_s3;

// ------------------------------------------------------------------
//  Stage 1：处理 bit7, bit6
//  step_0 = in_2[7] ? in_1 : 0
//  step_1 = gf_shift(step_0) ^ (in_2[6] ? in_1 : 0)
// ------------------------------------------------------------------
wire [7:0] stage1_step0 = in_2[7] ? in_1 : 8'h00;
wire [7:0] stage1_shift = stage1_step0[7] ?
                          ({stage1_step0[6:0], 1'b0} ^ 8'h1D) :
                           {stage1_step0[6:0], 1'b0};
wire [7:0] stage1_out   = stage1_shift ^ (in_2[6] ? in_1 : 8'h00);

always @(posedge clk) begin
    if (!rst_n) begin
        step_1_reg <= 8'd0;
        ca_vld_1   <= 1'b0;
        store_1    <= 8'd0;
        in1_s1     <= 8'd0;
    end else begin
        step_1_reg <= stage1_out;
        ca_vld_1   <= start;
        store_1    <= in_2;
        in1_s1     <= in_1;
    end
end

// ------------------------------------------------------------------
//  Stage 2：处理 bit5, bit4
//  step_2a = gf_shift(step_1) ^ (store_1[5] ? in1_s1 : 0)
//  step_2b = gf_shift(step_2a) ^ (store_1[4] ? in1_s1 : 0)
// ------------------------------------------------------------------
wire [7:0] stage2_shift_a = step_1_reg[7] ?
                            ({step_1_reg[6:0], 1'b0} ^ 8'h1D) :
                             {step_1_reg[6:0], 1'b0};
wire [7:0] stage2_step_a  = stage2_shift_a ^ (store_1[5] ? in1_s1 : 8'h00);

wire [7:0] stage2_shift_b = stage2_step_a[7] ?
                            ({stage2_step_a[6:0], 1'b0} ^ 8'h1D) :
                             {stage2_step_a[6:0], 1'b0};
wire [7:0] stage2_out     = stage2_shift_b ^ (store_1[4] ? in1_s1 : 8'h00);

always @(posedge clk) begin
    if (!rst_n) begin
        step_2_reg <= 8'd0;
        ca_vld_2   <= 1'b0;
        store_2    <= 8'd0;
        in1_s2     <= 8'd0;
    end else begin
        step_2_reg <= stage2_out;
        ca_vld_2   <= ca_vld_1;
        store_2    <= store_1;
        in1_s2     <= in1_s1;
    end
end

// ------------------------------------------------------------------
//  Stage 3：处理 bit3, bit2
//  step_3a = gf_shift(step_2) ^ (store_2[3] ? in1_s2 : 0)
//  step_3b = gf_shift(step_3a) ^ (store_2[2] ? in1_s2 : 0)
// ------------------------------------------------------------------
wire [7:0] stage3_shift_a = step_2_reg[7] ?
                            ({step_2_reg[6:0], 1'b0} ^ 8'h1D) :
                             {step_2_reg[6:0], 1'b0};
wire [7:0] stage3_step_a  = stage3_shift_a ^ (store_2[3] ? in1_s2 : 8'h00);

wire [7:0] stage3_shift_b = stage3_step_a[7] ?
                            ({stage3_step_a[6:0], 1'b0} ^ 8'h1D) :
                             {stage3_step_a[6:0], 1'b0};
wire [7:0] stage3_out     = stage3_shift_b ^ (store_2[2] ? in1_s2 : 8'h00);

always @(posedge clk) begin
    if (!rst_n) begin
        step_3_reg <= 8'd0;
        ca_vld_3   <= 1'b0;
        store_3    <= 8'd0;
        in1_s3     <= 8'd0;
    end else begin
        step_3_reg <= stage3_out;
        ca_vld_3   <= ca_vld_2;
        store_3    <= store_2;
        in1_s3     <= in1_s2;
    end
end

// ------------------------------------------------------------------
//  Stage 4：处理 bit1, bit0 → 最终输出
//  step_4a = gf_shift(step_3) ^ (store_3[1] ? in1_s3 : 0)
//  step_4b = gf_shift(step_4a) ^ (store_3[0] ? in1_s3 : 0)
// ------------------------------------------------------------------
wire [7:0] stage4_shift_a = step_3_reg[7] ?
                            ({step_3_reg[6:0], 1'b0} ^ 8'h1D) :
                             {step_3_reg[6:0], 1'b0};
wire [7:0] stage4_step_a  = stage4_shift_a ^ (store_3[1] ? in1_s3 : 8'h00);

wire [7:0] stage4_shift_b = stage4_step_a[7] ?
                            ({stage4_step_a[6:0], 1'b0} ^ 8'h1D) :
                             {stage4_step_a[6:0], 1'b0};
wire [7:0] stage4_out     = stage4_shift_b ^ (store_3[0] ? in1_s3 : 8'h00);

always @(posedge clk) begin
    if (!rst_n) begin
        out  <= 8'd0;
        done <= 1'b0;
    end else begin
        out  <= stage4_out;
        done <= ca_vld_3;
    end
end

endmodule