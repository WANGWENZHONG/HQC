// ============================================================
//  peak_detect.v  —  FHT峰值检测
//
//  输入：由哈达玛变换最后一级输出，每拍两个有符号数(din_a, din_b)连续64拍，共128个数
//        
//  输出：dout[7]   = 信息位判决（峰值为正且非零则为1）
//       dout[6:0] = 峰值位置索引（0~127）
// ============================================================
module peak_detect #(
    parameter PARAM_HQC = 128,
    parameter SUM_W          = (PARAM_HQC == 128) ? 2 : 3,
    parameter DIN_W          = 1 + SUM_W + 7,   // 有符号输入位宽
    parameter DOUT_W         = 8                 // 输出位宽
)(
    input                   clk,
    input                   rst_n,
    input                   data_in_start,      // 每批第一对数据前一拍拉高
    input  [DIN_W-1:0]      din_a,              // 偶数位置数据
    input  [DIN_W-1:0]      din_b,              // 奇数位置数据
    input                   din_valid,

    output reg [DOUT_W-1:0]     dout,               // {判决bit, 峰值位置}
    output reg                 	dout_valid
);

wire [DIN_W-1:0]    peak_value0, peak_value1, next_value;
wire [DIN_W-2:0]    peak_abs0,   peak_abs1;
wire [6:0]          peak_pos0,   peak_pos1,   next_pos;
wire                dout_valid0, dout_valid1;
wire                check_abs, check_equ, check_pos;


// ------------------------------------------------------------------
//  双核并行找峰值
//  核0处理 din_a（偶数位置：0,2,4,...,126）
//  核1处理 din_b（奇数位置：1,3,5,...,127）
// ------------------------------------------------------------------
findpeaks_core #(
    .PARAM_HQC	   (PARAM_HQC),
    .DIN_W         (DIN_W),
    .POS_W         (7),
    .STARTPOS      (0)          // 偶数核，从位置0开始，步进2
) u_core0 (
    .clk           (clk),
    .rst_n         (rst_n),
    .din_start     (data_in_start),
    .din_i         (din_a),
    .din_valid_i   (din_valid),
    .peak_abs      (peak_abs0),
    .peak_pos      (peak_pos0),
    .peak_value    (peak_value0),
    .dout_valid    (dout_valid0)
);

findpeaks_core #(
    .PARAM_HQC	   (PARAM_HQC),
    .DIN_W         (DIN_W),
    .POS_W         (7),
    .STARTPOS      (1)          // 奇数核，从位置1开始，步进2
) u_core1 (
    .clk           (clk),
    .rst_n         (rst_n),
    .din_start     (data_in_start),
    .din_i         (din_b),
    .din_valid_i   (din_valid),
    .peak_abs      (peak_abs1),
    .peak_pos      (peak_pos1),
    .peak_value    (peak_value1),
    .dout_valid    (dout_valid1)
);

//==================== 结果比较 ====================
assign check_abs = (peak_abs1 > peak_abs0);
assign check_equ = (peak_abs1 == peak_abs0);
assign check_pos = (peak_pos1 > peak_pos0);

assign next_value = (check_abs | (check_equ & check_pos)) ?
                     peak_value1 : peak_value0;
assign next_pos   = (check_abs | (check_equ & check_pos)) ?
                     peak_pos1  : peak_pos0;

// ------------------------------------------------------------------
//  输出寄存
//  dout[7]   = 信息位判决：峰值为正非零时为1，否则为0
//  dout[6:0] = 峰值位置
// ------------------------------------------------------------------
always @(posedge clk) begin
    dout_valid <= dout_valid0;
    dout       <= {~(next_value[DIN_W-1] || (next_value[DIN_W-2:0] == 0)),next_pos};
end

endmodule


// ============================================================
//  findpeaks_core.v  —  单路峰值检测核
//
//  每拍输入一个有符号数，与历史峰值比较绝对值，保留较大者
//  cnt_in 步进2，区分偶数/奇数全局位置
// ============================================================
module findpeaks_core #(
    parameter PARAM_HQC = 128,
    parameter DIN_W          = 10,  // 有符号输入位宽
    parameter POS_W          = 7,   // 位置索引位宽（0~127需要7bit）
    parameter STARTPOS       = 0    // 起始位置：0=偶数核，1=奇数核
)(
    input                   	clk,
    input                   	rst_n,
    input                   	din_start,    
    input  [DIN_W-1:0]      	din_i,
    input                   	din_valid_i,

    output reg [DIN_W-2:0]      peak_abs,     // 峰值绝对值
    output reg [POS_W-1:0]      peak_pos,     // 峰值位置
    output reg [DIN_W-1:0]      peak_value,   // 峰值原始值
    output reg                  dout_valid
);

//------------------------ 寄存器 ------------------------
reg [POS_W-1:0]     cnt_in;             // 全局位置计数，步进2
reg [DIN_W-1:0] 	din_i_reg;
reg [DIN_W-2:0] 	din_abs_reg;
wire [POS_W-1:0] 	din_pos = cnt_in;
reg             	din_valid_reg;
reg             	din_start_reg;

always @(posedge clk) begin
    if (!rst_n) begin
        din_i_reg     <= {DIN_W{1'b0}};
        din_abs_reg   <= {(DIN_W-1){1'b0}};
        din_valid_reg <= 1'b0;
        din_start_reg <= 1'b0;
    end else begin
        din_valid_reg <= din_valid_i;
        din_start_reg <= din_start;
        if (din_valid_i) begin
            din_i_reg   <= din_i;
            din_abs_reg <= din_i[DIN_W-1] ? (~din_i[DIN_W-2:0] + 1'b1) : din_i[DIN_W-2:0];
        end
    end
end	
// 2. 使用打拍后的数据和控制信号进行第二级处理
wire [DIN_W-2:0]    prev_abs   = din_start_reg ? {(DIN_W-1){1'b0}} : peak_abs;
wire [POS_W-1:0]    prev_pos   = din_start_reg ? STARTPOS[POS_W-1:0] : peak_pos;
wire [DIN_W-1:0]    prev_value = din_start_reg ? {DIN_W{1'b0}} : peak_value;

//==================== 比较与更新 ====================
wire check_abs = (din_abs_reg > prev_abs);

wire [DIN_W-2:0]    next_abs   = check_abs ? din_abs_reg : prev_abs;
wire [POS_W-1:0]    next_pos   = check_abs ? din_pos	 : prev_pos;
wire [DIN_W-1:0]    next_value = check_abs ? din_i_reg   : prev_value;

always @(posedge clk) begin
    if (!rst_n) begin
        peak_abs   <= {(DIN_W-1){1'b0}};
        peak_pos   <= STARTPOS[POS_W-1:0];
        peak_value <= {DIN_W{1'b0}};
    end else if (din_valid_reg) begin
        peak_abs   <= next_abs;
        peak_pos   <= next_pos;
        peak_value <= next_value;
    end
end

// ------------------------------------------------------------------
//  位置计数器：步进2，区分奇偶全局位置
//  start_i或last_din时复位到STARTPOS
// ------------------------------------------------------------------
wire last_din = (cnt_in[6:1] == 6'd63) && din_valid_reg;

always @(posedge clk) begin
    if (!rst_n)
        cnt_in <= STARTPOS[POS_W-1:0];
    else if (last_din)
        cnt_in <= STARTPOS[POS_W-1:0];
    else if (din_valid_reg)
        cnt_in <= cnt_in + 2'd2;
end

//==================== 输出有效 ====================
always @(posedge clk) begin
    if (!rst_n) 
		dout_valid <= 1'b0;
    else        
		dout_valid <= last_din;
end


endmodule