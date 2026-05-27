`timescale 1ns / 1ps
// ============================================================
//  RS_decode_top.v  —  RS译码顶层模块
//
//  子模块连接：
//    RS_syndrome  → 计算伴随式 + 缓存消息
//    RS_ePIMBA    → 计算误差定位/评估多项式
//    RS_error_ca  → Chien搜索 + Forney误差计算 + 消息纠错
//
//  数据流：
//    din → RS_syndrome → synd/msg → RS_ePIMBA → Lambda/omega/gamma/Z
//       → RS_error_ca → msg_out（纠错后消息）
// ============================================================
module RS_decode_top #(
    parameter PARAM_HQC      = 128,
    parameter T    			 = (PARAM_HQC == 128) ? 15 ://最多纠错数
                               (PARAM_HQC == 192) ? 16 :
                               (PARAM_HQC == 256) ? 29 : 15,
    parameter PARAM_N1       = (PARAM_HQC == 128) ? 46 :
                               (PARAM_HQC == 192) ? 56 :
                               (PARAM_HQC == 256) ? 90 : 46,
    parameter PARAM_K        = (PARAM_HQC == 128) ? 16 :
                               (PARAM_HQC == 192) ? 24 :
                               (PARAM_HQC == 256) ? 32 : 16,
    parameter SYND_NUM       = 2 * T,
    parameter POLYNUM        = 2 * T + 1,
    parameter DIN_W          = 8,
    parameter DOUT_W         = 8 * SYND_NUM,
    parameter MSG_W          = 8 * PARAM_K,
    parameter LAMBDA_W       = 8 * (T + 1),
    parameter OMEGA_W        = 8 * T,
    parameter CNT_W          = (PARAM_HQC == 256) ? 7 : 6
)(
    input                        clk,
    input                        rst_n,
    input  [DIN_W-1:0]           din,
    input                        din_valid,
    // 输出
    output [MSG_W-1:0]           msg_out,    // 纠错后消息
    output                       done,     	 // 译码完成
    output                       din_ready   // 可接收下一个输入
);


wire [DOUT_W-1:0]   synd_dout;       // 伴随式（2T个字节）
wire                synd_dout_valid; // 伴随式有效
wire [MSG_W-1:0]    msg_from_synd;   // 原始接收消息（最后K个字节）

// RS_ePIMBA → RS_error_ca
wire [LAMBDA_W-1:0] lambda_out;      // Lambda多项式（T+1字节）
wire [OMEGA_W-1:0]  omega_out;       // Omega多项式（T字节，来自sitax前T项）
wire [7:0]          gamma_out;       // gamma
wire [5:0]          z_cnt_out;       // z
wire [7:0]          L_sigma_out;     // Lambda次数
wire                epimba_out_vld;  // ePIMBA输出有效


// ------ 子模块1：综合征计算 ------
RS_syndrome #(
    .PARAM_HQC  (PARAM_HQC)
) RS_syndrome_inst (
    .clk        (clk),
    .rst_n      (rst_n),
    .din        (din),
    .din_valid  (din_valid),
    .din_ready  (din_ready),
    .dout       (synd_dout),
    .dout_valid (synd_dout_valid),
    .msg_out    (msg_from_synd)
);
// ------ 子模块2：计算误差定位/评估多项式 ------
RS_ePIMBA #(
    .PARAM_HQC   (PARAM_HQC)
) RS_ePIMBA_inst (
    .clk        (clk),
    .rst_n      (rst_n),
    .synd       (synd_dout),
    .synd_vld   (synd_dout_valid),
    .lambda     (lambda_out),
	.omega_out	(omega_out),
    .gamma      (gamma_out),
    .z_cnt      (z_cnt_out),
    .L_sigma    (L_sigma_out),
    .out_vld    (epimba_out_vld)
);


// ------ 子模块3：Chien搜索+误差计算+消息纠错 ------
RS_error_ca #(
    .PARAM_HQC (PARAM_HQC)
) RS_error_ca_inst (
    .clk        (clk),
    .rst_n      (rst_n),
    .data_vld   (epimba_out_vld),   // ePIMBA完成时多项式有效
    .lambda     (lambda_out),
    .omega      (omega_out),
    .gamma      (gamma_out),
    .L_sigma    (L_sigma_out),
    .z_cnt      (z_cnt_out),
    .msg_vld    (synd_dout_valid),  // 消息由伴随式计算模块输出
    .msg_in     (msg_from_synd),
    .msg_out    (msg_out),
    .done     	(done)
);

endmodule
