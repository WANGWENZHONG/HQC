`timescale 1ns / 1ps
module RS_encode#( 
    parameter PARAM_HQC = 128,  //HQC参数                                                
    parameter PARAM_N1  = (PARAM_HQC == 128)? 46:
				          (PARAM_HQC == 192)? 56:
				          (PARAM_HQC == 256)? 90: 46,
	parameter PARAM_K   = (PARAM_HQC == 128)? 16:
				          (PARAM_HQC == 192)? 24:
			              (PARAM_HQC == 256)? 32: 16,
	parameter G_x_WIDTH = (PARAM_HQC == 128)? 256:
	                      (PARAM_HQC == 192)? 264:
	                      (PARAM_HQC == 256)? 480:256,    					  
	parameter G_x 		= (PARAM_HQC == 128)? 256'h0001B5FF_52E4454A_6EAED269_7643AD67_8B15D241_E9F2E949_4B6F75B0_74994559:
						  (PARAM_HQC == 192)? 264'h01_E81DBD32_8EF6E80F_2B52A4EE_019E0D77_9EE086E3_D2A3326B_281B68FD_18EFD82D:
						  (PARAM_HQC == 256)? 480'h0001bbc7_30d8bc27_2f7c4082_b28d1b2f_e80890bf_f6048d63_ef98dbb4_f31f0c7b_d98db7ba_d26173c9_479fd720_65577b96_47943ff0_5b7c79c8_2731a731:
	                                             256'h0001B5FF_52E4454A_6EAED269_7643AD67_8B15D241_E9F2E949_4B6F75B0_74994559,  
	parameter REG_NUM 	= (PARAM_HQC == 128)? 30:
						  (PARAM_HQC == 192)? 32:
	                      (PARAM_HQC == 256)? 58: 30,  
	parameter CNT_W 	=  (PARAM_HQC == 256)? 6: 5,  
	parameter N1 = 8*PARAM_N1,
	parameter K =  8*PARAM_K				
)
(
    input 		  			clk,            // 系统时钟
    input 		  			rst_n,          // 异步复位，低有效
    input 		[K-1:0]   	msg_in,         // 输入消息
	input		  			msg_in_vld,	    // 消息有效指示
	output reg		  		msg_out_vld,    // 输出有效指示
    output reg  [7:0] 		msg_out,        // 编码输出字节（高位先输出）
    output reg 	 			done            // 一帧编码完成信号
    );
	
wire 			[7:0] 			gate_value;
reg				[K-1:0]			msg_reg;
reg				[7:0] 			ca_reg[0:REG_NUM-1];
wire			[7:0] 			gf_mul_out[0:REG_NUM-1];
wire            [REG_NUM-1:0]   gf_out_vld_arr;
wire							gf_out_vld = gf_out_vld_arr[0];
reg								gf_in_vld;
reg				[CNT_W-1 :0]	gf_ca_cnt;
reg			[6:0]			reg_out_cnt;	
reg								reg_out_vld;
				
//==================== 有限域多项式乘法 ====================
assign	gate_value = msg_reg[K-1-:8] ^ ca_reg[REG_NUM-1];
// 反馈值 = 当前消息最高字节 ^ LFSR最高位寄存器值
genvar j;
//采用4拍输出的GF乘法器
generate 
    for (j=0; j<REG_NUM; j =j+1) begin
		gf_mul_pipline_4 	gf_encode (
			.clk  			(clk),
			.rst_n			(rst_n),
			.start			(gf_in_vld),
			.in_1 			(gate_value),
			.in_2 			(G_x[j*8+:8]),
			.out  			(gf_mul_out[j]),
			.done 			(gf_out_vld_arr[j])
		);
    end
endgenerate 
//==================== 寄存器更新 ====================
integer	i;
// LFSR状态更新：gf_out_vld有效时，执行一次移位异或
always@(posedge clk)begin
	if (!rst_n)begin
		for (i = 0;i<REG_NUM;i=i+1)begin
			ca_reg[i] <= 8'd0;
		end
	end
	else if (msg_in_vld) begin 
        for (i = 0;i<REG_NUM;i=i+1) begin
			ca_reg[i] <= 8'd0;
		end
    end
	else if (gf_out_vld)begin
		ca_reg[0] <= gf_mul_out[0];
		for (i = 1;i<REG_NUM;i=i+1)begin
			ca_reg[i] <= ca_reg[i-1]^gf_mul_out[i];
		end
	end
end
//==================== 数据寄存 ====================
always@(posedge clk)begin
	if (msg_in_vld)
		msg_reg <= msg_in;
	else if (gf_in_vld)
		msg_reg <= {msg_reg[K-9:0],8'd0};
end
//==================== 计数器 ====================
// gf_ca_cnt：记录已完成的乘法次数，即已处理的消息字节数（0 ~ PARAM_K）
always@(posedge clk)begin
	if (!rst_n)
		gf_ca_cnt <= 'd0;
	else if (gf_out_vld)
		gf_ca_cnt <= gf_ca_cnt + 1'b1;
	else if (done)
		gf_ca_cnt <= 'd0;
end

// reg_out_cnt：校验输出字节计数（0 ~ REG_NUM-1）
always@(posedge clk)begin
	if (!rst_n)
		reg_out_cnt <= 'd0;
	else if (reg_out_vld)
		reg_out_cnt <= reg_out_cnt + 1'b1;
	else if (done)
		reg_out_cnt <= 'd0;
end
//==================== 使能信号 ====================
// reg_out_vld：校验输出有效标志，当消息字节全部输入后拉高，持续REG_NUM个周期
always@(posedge clk)begin
	if (!rst_n)
		reg_out_vld <= 1'b0;
	else if ((reg_out_cnt == REG_NUM-1)||(done))
		reg_out_vld <= 1'b0;
	else if (gf_ca_cnt == PARAM_K)
		reg_out_vld <= 1'b1;
end
// gf_in_vld：GF乘法器启动脉冲，在需要计算下一次反馈时拉高一个周期
always@(posedge clk)begin
	if ((msg_in_vld || gf_out_vld) && (gf_ca_cnt != PARAM_K-1))
		gf_in_vld <= 1'b1;
	else
		gf_in_vld <= 1'b0;
end
//==================== 输出信号 ====================
always@(posedge clk)begin
	msg_out_vld <= gf_in_vld || reg_out_vld;
end
// msg_out：编码输出字节，先输出消息（gf_in_vld有效时），后输出校验（reg_out_vld有效时）
always@(posedge clk)begin
	if (!rst_n)
		msg_out <= 8'd0;
	else if(gf_in_vld)
		msg_out <= msg_reg[K-1-:8];
	else if (reg_out_vld)
		msg_out <= ca_reg[REG_NUM - reg_out_cnt -1];
end

always@(posedge clk)begin
	if (!rst_n)
		done <= 1'b0;
	else if (reg_out_cnt == REG_NUM-1)
		done <= 1'b1;
	else 
		done <= 1'b0;
end


    
    
endmodule

