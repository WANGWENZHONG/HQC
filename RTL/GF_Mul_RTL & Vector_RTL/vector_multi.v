// =====================================================================
// 模块名称: vector_multi
// 主要功能: HQC稀疏多项式乘法的移位累加子模块（Expansion阶段的核心引擎）。
// 实现方式: 接收非零索引和稠密多项式数据，利用桶形移位器拼接并移位（展开），
//           与自带的双端口RAM中缓存的历史数据进行异或累加。
//           在输出阶段，实现了“边读边清空（Clear-on-Read）”以准备下一轮，
//           并具备将跨字数据拼接（位偏移5 bit）的功能，支持后续的17669模约减。
// =====================================================================

// =====================================================================
// 模块名称: vector_multi (Expansion 阶段)
// 功能描述: 移位累加器。
// 在 out_en 触发输出时，执行“边读边清空 (Clear-on-Read)”。
// =====================================================================
module vector_multi #(
    parameter   CNT_W = 277,
	parameter	HALF_W = 139
)(
    input                   clk,
    input                   rst_n,
    input       [127:0]     poly_in,
    input                   poly_in_vld,
    input                   poly_in_last,
    input       [14:0]      poly_index, 
    input                   index_vld,  
    input                   out_en,      // 脉冲信号，完成所有非0坐标输出后，触发读取输出序列
    output reg              read_out_en, 
	output reg				out_en_extra,
    output reg     [127:0]  data_out 
);

//------------------------ 变量声明 ------------------------
reg  [127:0] poly_in_reg;
reg  [14:0]  index_reg;
reg          flushing;      

reg  [8:0]   poly_radr; 
reg  [8:0]   poly_wadr;
reg  [8:0]   poly_wadr_dly; 
reg  [8:0]   poly_wadr_2dly; 

reg          in_vld_dly, in_vld_2dly, in_vld_3dly;

reg  [127:0] data_ram_in;

// ---边读边清零逻辑变量 ---
reg  [8:0]   init_cnt;
reg          read_out_en_dly;
reg  [8:0]   poly_radr_dly;
reg          read_out_en_pre;

//------------------------ 数据与索引缓存 ------------------------
always @(posedge clk) begin
	if(!rst_n)
		poly_in_reg <= 128'd0;
	else if (poly_in_vld)
		poly_in_reg <= poly_in;
	else if (flushing)
		poly_in_reg <= 128'd0;
end

always @(posedge clk) begin
    if (!rst_n)
        index_reg <= 15'd0;
	else if (index_vld)
		index_reg <= poly_index;
end

always @(posedge clk) begin
    flushing <= poly_in_last;
end

//------------------------ 地址管理 (读地址) ------------------------
always @(posedge clk) begin
    if (!rst_n) 	
        poly_radr <= 9'd0;
	else if (index_vld) 	
        poly_radr <= poly_index[14:7];
	else if (out_en || (poly_radr == CNT_W))  
        poly_radr <= 9'd0; // out_en 触发时，读指针归零开始扫数据
    else if (poly_in_vld || flushing || read_out_en_pre)  
        poly_radr <= poly_radr + 1'b1;
end

//------------------------ 边读边清零 (Clear-on-Read) 对齐 ------------------------
// 因为 RAM 读出需要 1 拍，当 B 端口读出第 X 个地址的数据时，
// A 端口利用打了一拍的读地址和使能，紧跟着把第 X 个地址写成 0。
always @(posedge clk) begin
    if (!rst_n) begin
        read_out_en_dly <= 1'b0;
        poly_radr_dly   <= 9'd0;
    end else begin
        read_out_en_dly <= read_out_en;
        poly_radr_dly   <= poly_radr;
    end
end

//------------------------ 地址流水线对齐 (累加写地址) ------------------------
always @(posedge clk) begin
    if (!rst_n) begin
        poly_wadr      <= 9'd0;
        poly_wadr_dly  <= 9'd0;
        poly_wadr_2dly <= 9'd0;
    end 
	else begin
        poly_wadr <= poly_radr;
        poly_wadr_dly  <= poly_wadr; 
        poly_wadr_2dly <= poly_wadr_dly; 
    end
end

//------------------------ 控制信号打拍 ------------------------
// [注释] 将输入有效信号沿流水线延时，以对齐移位和RAM的读取延迟
always @(posedge clk)begin
    if (!rst_n) begin
        in_vld_dly  <= 1'b0;
        in_vld_2dly <= 1'b0;
        in_vld_3dly <= 1'b0;
	end
    else begin
        in_vld_dly  <= poly_in_vld || flushing;
        in_vld_2dly <= in_vld_dly;
        in_vld_3dly <= in_vld_2dly;
    end
end

always @(posedge clk) begin
    if (!rst_n)
        read_out_en_pre <= 1'b0;
	else if (out_en)
        read_out_en_pre <= 1'b1;
	else if (poly_radr == CNT_W)
        read_out_en_pre <= 1'b0;
end

always @(posedge clk) begin
    read_out_en <= read_out_en_pre;

end
//------------------------ 数据移位与异或 (Pipeline) ------------------------
// [注释] 核心计算通路：256-bit位宽拼接窗口，利用组合逻辑完成循环/溢出右移
wire 		[127:0] 	current_poly = flushing ? 128'd0 : poly_in;
wire 		[255:0] 	shift_window = {current_poly, poly_in_reg};
wire		[127:0]		data_ram_out;
reg 		[127:0] 	shifted_data_reg;

always @(posedge clk) begin
    shifted_data_reg <= shift_window >> (128-index_reg[6:0]);
end

always @(posedge clk) begin
    if (!rst_n)
        data_ram_in <= 128'd0;
    else if (in_vld_dly)
        data_ram_in <= data_ram_out ^ shifted_data_reg;
	else
		data_ram_in <= 128'd0;
end

//------------------------ RAM 端口复用逻辑 ------------------------
// 累加计算写入
// 输出并清零
// [注释] 根据当前阶段，决定是写入累加结果还是通过写0清空当前地址
wire [8:0]   wram_addra =  in_vld_2dly ? poly_wadr_dly:
							read_out_en_dly ? poly_radr_dly : 9'd0;

// 当两种情况任意一个发生时，拉高写使能
wire         ram_wea   = in_vld_2dly||read_out_en_dly;
//双端口ram，一个端口只写，一个端口只读，每个地址存储128bit数据，共278个数据
//需要用coe文件将ram初始化为全0数据
vector_ram vector_ram_inst(
    .clka   (clk),
    .addra  (wram_addra),
    .dina   (data_ram_in),
    .ena    (1'b1),
    .wea    (ram_wea),
    // 端口 B 纯粹用于读取
    .clkb   (clk),
    .addrb  (poly_radr),
    .doutb  (data_ram_out),
    .enb    (1'b1)
);
//------------------------ 输出逻辑 ------------------------
reg		  [122:0]		    data_out_reg;
reg							out_en_extra_pre;

// [注释] 模约减折叠拼接：截取当前字低5位与上一个字高123位拼接，等价于整体右移5bit
always @(*) begin
	if (out_en_extra)
		data_out = {data_ram_out[4:0],data_out_reg};
	else if (read_out_en)
		data_out = data_ram_out;
	else 
		data_out = 128'd0;
end

always @(posedge clk) begin
    if (!rst_n)
        data_out_reg <= 123'd0;
	else if (read_out_en)
        data_out_reg <= data_ram_out[127:5];
end

always @(posedge clk) begin
    if (poly_radr == CNT_W)
		out_en_extra_pre <= 1'b1;
	else
		out_en_extra_pre <= 1'b0;
end

always @(posedge clk) begin
    if (!rst_n)
        out_en_extra <= 1'b0;
	else if (poly_radr == HALF_W)
        out_en_extra <= read_out_en;
	else if (out_en_extra_pre)
        out_en_extra <= 1'b0;
end

endmodule