// ============================================================
//  RM_HA_top.v  —  哈达玛变换顶层
//
//  输入：由求和模块输出，采用流水线输入，可以流水完成多个译码
//        
//  输出：每拍两个有符号数(din_a, din_b)连续64拍，共128个数
// ============================================================
module RM_HA_top #(
    parameter PARAM_HQC = 128,
    parameter MULTIPLICITY   = (PARAM_HQC == 128) ? 3 : 5,
    parameter DATE_SUM_W     = (PARAM_HQC == 128) ? 2 : 3,
    parameter DATE_HA_W      = (PARAM_HQC == 128) ? 10 : 11
)(
    input                        clk,
    input                        rst_n,
    input                        data_in_start,
    input  [DATE_SUM_W-1:0]      data_sum_0,
    input  [DATE_SUM_W-1:0]      data_sum_1,
    input                        data_sum_vld,
    output                       data_HA_vld,
    output [DATE_HA_W-1:0]       data_HA_0,
    output [DATE_HA_W-1:0]       data_HA_1,
    output                       data_HA_start
);
wire        valid_0, valid_1, valid_2, valid_3;
wire        valid_4, valid_5, valid_6, valid_7;
wire        start_0, start_1, start_2, start_3;
wire        start_4, start_5, start_6, start_7;

// Layer0 输入（来自外部，DATE_SUM_W=2bit）
wire [DATE_SUM_W:0]  l0_in_a,  l0_in_b;
// Layer0 输出 / Layer1 输入（3bit）
wire [DATE_SUM_W+1:0]  l0_out_a, l0_out_b;
// Layer1 输出 / Layer2 输入（4bit）
wire [DATE_SUM_W+2:0]  l1_out_a, l1_out_b;
// Layer2 输出 / Layer3 输入（5bit）
wire [DATE_SUM_W+3:0]  l2_out_a, l2_out_b;
// Layer3 输出 / Layer4 输入（6bit）
wire [DATE_SUM_W+4:0]  l3_out_a, l3_out_b;
// Layer4 输出 / Layer5 输入（7bit）
wire [DATE_SUM_W+5:0]  l4_out_a, l4_out_b;
// Layer5 输出 / Layer6 输入（8bit）
wire [DATE_SUM_W+6:0]  l5_out_a, l5_out_b;
// Layer6 输出（9bit），零扩展到DATE_HA_W后输出
wire [DATE_SUM_W+7:0]  l6_out_a, l6_out_b;

//==================== Layer 0 ====================
assign l0_in_a = {1'b0,data_sum_0};
assign l0_in_b = {1'b0,data_sum_1};
assign valid_0 = data_sum_vld;
assign start_0 = data_in_start;
ha_layer #(
    .DATA_IN_W (DATE_SUM_W+1),
    .DATA_OUT_W(DATE_SUM_W+2),
    .STAGE_IDX (0)
) u_layer0 (
    .clk       (clk),
    .rst_n     (rst_n),
    .din_valid (valid_0),
    .din_start (start_0),
    .din_a     (l0_in_a),
    .din_b     (l0_in_b),
    .dout_valid(valid_1),
    .dout_start(start_1),
    .dout_a    (l0_out_a),
    .dout_b    (l0_out_b)
);

//==================== Layer 1 ====================
ha_layer #(
    .DATA_IN_W (DATE_SUM_W+2),
    .DATA_OUT_W(DATE_SUM_W+3)
) u_layer1 (
    .clk       (clk),
    .rst_n     (rst_n),
    .din_valid (valid_1),
    .din_start (start_1),
    .din_a     (l0_out_a),
    .din_b     (l0_out_b),
    .dout_valid(valid_2),
    .dout_start(start_2),
    .dout_a    (l1_out_a),
    .dout_b    (l1_out_b)
);

//==================== Layer 2 ====================
ha_layer #(
    .DATA_IN_W (DATE_SUM_W+3),
    .DATA_OUT_W(DATE_SUM_W+4)
) u_layer2 (
    .clk       (clk),
    .rst_n     (rst_n),
    .din_valid (valid_2),
    .din_start (start_2),
    .din_a     (l1_out_a),
    .din_b     (l1_out_b),
    .dout_valid(valid_3),
    .dout_start(start_3),
    .dout_a    (l2_out_a),
    .dout_b    (l2_out_b)
);

//==================== Layer 3 ====================
ha_layer #(
    .DATA_IN_W (DATE_SUM_W+4),
    .DATA_OUT_W(DATE_SUM_W+5)
) u_layer3 (
    .clk       (clk),
    .rst_n     (rst_n),
    .din_valid (valid_3),
    .din_start (start_3),
    .din_a     (l2_out_a),
    .din_b     (l2_out_b),
    .dout_valid(valid_4),
    .dout_start(start_4),
    .dout_a    (l3_out_a),
    .dout_b    (l3_out_b)
);

//==================== Layer 4 ====================
ha_layer #(
    .DATA_IN_W (DATE_SUM_W+5),
    .DATA_OUT_W(DATE_SUM_W+6)
) u_layer4 (
    .clk       (clk),
    .rst_n     (rst_n),
    .din_valid (valid_4),
    .din_start (start_4),
    .din_a     (l3_out_a),
    .din_b     (l3_out_b),
    .dout_valid(valid_5),
    .dout_start(start_5),
    .dout_a    (l4_out_a),
    .dout_b    (l4_out_b)
);

//==================== Layer 5 ====================
ha_layer #(
    .DATA_IN_W (DATE_SUM_W+6),
    .DATA_OUT_W(DATE_SUM_W+7)
) u_layer5 (
    .clk       (clk),
    .rst_n     (rst_n),
    .din_valid (valid_5),
    .din_start (start_5),
    .din_a     (l4_out_a),
    .din_b     (l4_out_b),
    .dout_valid(valid_6),
    .dout_start(start_6),
    .dout_a    (l5_out_a),
    .dout_b    (l5_out_b)
);

//==================== Layer 6 ====================
ha_layer #(
    .DATA_IN_W (DATE_SUM_W+7),
    .DATA_OUT_W(DATE_SUM_W+8)
) u_layer6 (
    .clk       (clk),
    .rst_n     (rst_n),
    .din_valid (valid_6),
    .din_start (start_6),
    .din_a     (l5_out_a),
    .din_b     (l5_out_b),
    .dout_valid(valid_7),
    .dout_start(start_7),
    .dout_a    (l6_out_a),
    .dout_b    (l6_out_b)
);

//==================== 最终输出 ====================
assign data_HA_vld   = valid_7;
assign data_HA_start = start_7;
assign data_HA_0 	 = start_7 ? (l6_out_a-64*MULTIPLICITY) : l6_out_a; //首项需要进行减法处理
assign data_HA_1     = l6_out_b;

endmodule