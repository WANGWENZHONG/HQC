// =====================================================================
// 模块名称: vector_multi_top
// 主要功能: HQC稀疏多项式乘法器的顶层调度控制模块。
// 实现方式: 协调两个 vector_multi 子模块并行处理不同的非零坐标索引（显著提高吞吐量）。
//           高度复用顶层BRAM：在输入期作为 D(x) 的主缓存池，计算期流送数据给子模块，
//           在最终的输出期又转换为“折叠缓冲池”。最终将两个子模块展开的结果汇总，
//           并利用低半区与高半区的 XOR 完成模 X^17669 - 1 的最终代数约减。
// =====================================================================

`timescale 1ns / 1ps

module vector_multi_top #(
    parameter N       = 17669,
    parameter WT_IN   = 65,
    parameter CNT_W   = 139
)(
    input                        clk,
    input                        rst_n,
    
    input      [127:0]           poly_in,
    input                        poly_vld,
	input						 poly_in_last,
    input      [15*WT_IN-1:0]    nonzero_index,
    input                        index_vld,
    
    output reg    [127:0]        poly_out,
    output reg                   out_vld
);
//------------------------ 变量声明 ------------------------
//index管理信号
reg 		[14:0] 		 index_reg [0:WT_IN-1];
reg			[6:0]		 index_cnt;
//RAM信号
reg 		[8:0] 		 wram_addra;
reg 		[8:0] 		 rram_addra;
wire		[127:0]      data_ram_in;
wire		[127:0]		 data_ram_out;
wire				 	 ram_wea;
//使能信号
reg					 	 next_vld;
wire					 sub_in_last;
reg				 		 sub_in_last_dly;
reg				 		 sub_in_last_2dly;
reg						 ram_out_vld_last;
reg						 stream_read_vld;
reg						 stream_read_vld_dly;
//子模块信号
wire		[127:0]		 poly_sub_in;
wire		[127:0]		 sub_ram_out_1;
wire		[127:0]		 sub_ram_out_2;
wire					 sub_in_vld_1;
wire					 sub_in_vld_2;
wire				     sub_2_vld;//index数量为奇数时在最后一个索引时拉低
reg		[14:0]		 	 sub_index_1;
reg		[14:0]		 	 sub_index_2;
reg						 sub_index_vld;
reg						 sub_out_wr;
reg						 sub_out_en;
wire					 sub_out;
wire					 sub_out_read;
reg			[127:0]		 sub_out_data;
//------------------------ 非0坐标存储 ------------------------
// [注释] 读取并缓存整个稀疏索引序列B(x)
integer i;
always @(posedge clk) begin
    if (!rst_n) begin
        for (i = 0; i < WT_IN; i = i + 1)
            index_reg[i] <= 15'd0;
    end else if (index_vld) begin
        for (i = 0; i < WT_IN; i = i + 1)
            index_reg[i] <= nonzero_index[15*i +: 15];
    end
end

//------------------------RAM 写入 ------------------------
// [注释] 顶层RAM写地址：复用于写入外部D(x)与子模块算完折叠前吐出的低半区
always @(posedge clk) begin
    if (!rst_n) 
        wram_addra <= 9'd0;
	else if (poly_vld||sub_out_wr) 
        wram_addra <= wram_addra + 1'b1;
	else if (poly_in_last||sub_out_en||out_vld)
		wram_addra <= 9'd0;
		
end

always @(posedge clk) begin
    stream_read_vld_dly <= stream_read_vld;
end
//------------------------ RAM 数据读出 ------------------------
always @(posedge clk) begin
    if (!rst_n) 
        rram_addra <= 9'd0;
	else if (sub_in_last_dly||poly_vld) 
        rram_addra <= 9'd0;
	else if (stream_read_vld||sub_out_read)
		rram_addra <= rram_addra + 1'b1;
	
end
//------------------------ 控制信号 ------------------------
// [注释] 调度分配任务给子模块，一旦一组计算结束，立即拉高next_vld进入下一轮
always @(posedge clk) begin
	if ((index_cnt != WT_IN)&&(sub_in_last_dly)&&(index_cnt != WT_IN+1)) 
        next_vld <= 1'b1;
	else 
		next_vld <= 1'b0;
end

always @(posedge clk) begin
    sub_in_last_dly <=	sub_in_last;
	sub_in_last_2dly<= sub_in_last_dly;
end

always @(posedge clk) begin
	if ((rram_addra == CNT_W-1)&&(stream_read_vld))
		ram_out_vld_last <= 1'b1;
	else 
		ram_out_vld_last <= 1'b0;
end

always @(posedge clk) begin
	if (!rst_n)
		stream_read_vld <= 1'b0;
	else if (next_vld)
		stream_read_vld <= 1'b1;
	else if(sub_in_last||poly_vld)
		stream_read_vld <= 1'b0;
end
//------------------------ 计数器 ------------------------
// [注释] index_cnt步进值为2，因为两个子模块并行处理，一次消耗两个索引
always @(posedge clk) begin
    if (!rst_n) 
        index_cnt <= 7'd0;
	else if (sub_in_last) 
        index_cnt <= index_cnt + 2'd2;
	else if (poly_vld)
		index_cnt <= 7'd0;
end

//------------------------ 子模块输入 ------------------------
assign  sub_2_vld = (index_cnt != WT_IN-1);

assign 	poly_sub_in = poly_vld? poly_in : data_ram_out;

assign  sub_in_vld_1 = poly_vld||stream_read_vld_dly;

assign  sub_in_vld_2 = sub_in_vld_1 && sub_2_vld;

assign  sub_in_last = poly_in_last||ram_out_vld_last;

always @(posedge clk) begin
    sub_index_vld <= index_vld || next_vld;
end

always @(posedge clk) begin
    if (next_vld)
        sub_index_1 <= index_reg[index_cnt];
	else
        sub_index_1 <= nonzero_index[14:0];
end
//第139组数据只取前5个
always @(posedge clk) begin
    if (next_vld && sub_2_vld)
        sub_index_2 <= index_reg[index_cnt + 1'b1];
	else
        sub_index_2 <= nonzero_index[29:15];
end

//------------------------ 子模块例化 ------------------------
vector_multi vector_multi_inst_1(
	.clk				(clk),
	.rst_n				(rst_n),
	.poly_in			(poly_sub_in),
    .poly_in_vld		(sub_in_vld_1),
    .poly_in_last		(sub_in_last),
    .poly_index			(sub_index_1),
    .index_vld   		(sub_index_vld),
    .out_en     		(sub_out_en),
    .read_out_en 		(sub_out),
	.out_en_extra 		(sub_out_read),
    .data_out 			(sub_ram_out_1)
);

vector_multi vector_multi_inst_2(
	.clk				(clk),
	.rst_n				(rst_n),
	.poly_in			(poly_sub_in),
    .poly_in_vld		(sub_in_vld_2),
    .poly_in_last		(sub_in_last),
    .poly_index			(sub_index_2),
    .index_vld   		(sub_index_vld),
    .out_en     		(sub_out_en),
    .read_out_en 		(),
	.out_en_extra 		(),
    .data_out 			(sub_ram_out_2)
);

//------------------------ 输出逻辑 ------------------------
always @(posedge clk) begin
	if (((index_cnt == WT_IN)||(index_cnt == WT_IN + 1)) &&(sub_in_last_2dly))
        sub_out_en <= 1'b1;
	else 
		sub_out_en <= 1'b0;
end

always @(posedge clk) begin
	sub_out_wr  <= sub_out ^ sub_out_read;
end

always @(posedge clk) begin
	out_vld  <= sub_out_read;
end

always @(posedge clk) begin
	sub_out_data <= sub_ram_out_1 ^ sub_ram_out_2;
end

// [注释] 最终折叠结果：将子模块流出的高半区与RAM读出的低半区按位异或


always @(*) begin
	if (rram_addra == CNT_W)
		poly_out = {123'd0,data_ram_out[4:0]^sub_out_data[4:0]};
	else
		poly_out = sub_out_data ^ data_ram_out;
end


//------------------------ 内部 RAM 例化 ------------------------
assign		data_ram_in = poly_vld ? poly_in : sub_out_data;

assign		ram_wea = poly_vld||sub_out_wr;
//双端口ram，一个端口只写，一个端口只读，每个地址存储128bit数据，共278个数据
vector_ram vector_ram_inst(
    .clka   			(clk),
    .addra  			(wram_addra),
    .dina   			(data_ram_in),
    .ena    			(1'b1),
    .wea    			(ram_wea),
			
    .clkb   			(clk),
    .addrb  			(rram_addra),
    .doutb  			(data_ram_out),
    .enb    			(1'b1)
);

endmodule