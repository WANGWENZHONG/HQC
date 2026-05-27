// ====================================================================
// RM_encode - Reed-Muller (RM) 编码器
// 功能：将8位信息字节扩展为128位编码输出
// 原理：根据输入字节的每一位，选择对应的32位固定编码向量，
//       多个向量通过异或叠加，最终拼成128位码字。
// 流水线：3级流水（en_vector -> vector -> encode_out），输出组合给出。
// bit7为常数项
// ====================================================================
module RM_encode
#( 	
	parameter ENCODING_VECTOR_0	= 	32'haaaaaaaa,
	parameter ENCODING_VECTOR_1	= 	32'hcccccccc,
	parameter ENCODING_VECTOR_2	= 	32'hf0f0f0f0,
	parameter ENCODING_VECTOR_3	= 	32'hff00ff00,
	parameter ENCODING_VECTOR_4	= 	32'hffff0000,
	parameter ENCODING_VECTOR_5	= 	32'hffffffff
)
(
    input 								clk,
    input 								rst_n,
    input 			[7:0] 				byte_in,
	input								byte_vld,
    output 			[127:0] 			encode_out,
    output reg 							out_vld
    );
    
// ====================================================================
// 第一级寄存器：向量选择
// 根据 byte_in 的每一位，选择对应的 ENCODING_VECTOR 或 0
// 若不选通，该向量贡献为全0，实现信息比特的掩码控制
// ====================================================================
reg [31:0] en_vector [0:7];

always@(posedge clk)
begin
    if (byte_in[0])
        en_vector[0] <= ENCODING_VECTOR_0;
    else
        en_vector[0] <= 0;
end

always@(posedge clk)
begin
    if (byte_in[1])
        en_vector[1] <= ENCODING_VECTOR_1;
    else 
        en_vector[1] <= 0;
end

always@(posedge clk)
begin
    if (byte_in[2])
        en_vector[2] <= ENCODING_VECTOR_2;
    else
        en_vector[2] <= 0;
end

always@(posedge clk)
begin
    if (byte_in[3])
        en_vector[3] <= ENCODING_VECTOR_3;
    else
        en_vector[3] <= 0;
end

always@(posedge clk)
begin
    if (byte_in[4])
        en_vector[4] <= ENCODING_VECTOR_4;
    else 
        en_vector[4] <= 0;
end

always@(posedge clk)
begin
    if (byte_in[5])
        en_vector[5] <= ENCODING_VECTOR_5;
    else 
        en_vector[5] <= 0;
end

always@(posedge clk)
begin
    if (byte_in[6])
        en_vector[6] <= ENCODING_VECTOR_5;
    else
        en_vector[6] <= 0;
end

always@(posedge clk)
begin
	if (byte_in[7])
        en_vector[7] <= ENCODING_VECTOR_5;
    else
        en_vector[7] <= 0;
end
// ====================================================================
// 计算异或结果
// ====================================================================

reg [31:0]	vector_0;
reg [31:0]  vector_1;
reg [31:0]  vector_2;
reg [31:0]  vector_3;
reg [31:0]  vector_4;
reg [31:0] encode_out_0_32;
reg [31:0] encode_out_1_32;
reg [31:0] encode_out_2_32;
reg [31:0] encode_out_3_32;

always @(posedge clk) begin
    if (!rst_n) begin
        vector_0 <= 32'd0;
        vector_1 <= 32'd0;
        vector_2 <= 32'd0;
        vector_3 <= 32'd0;
		vector_4 <= 32'd0;
    end 
	else begin
        vector_0 <= en_vector[0] ^ en_vector[1] ^ en_vector[2];
        vector_1 <= en_vector[3] ^ en_vector[4] ^ en_vector[7];
		vector_2 <= en_vector[5];
		vector_3 <= en_vector[6];
		vector_4 <= en_vector[5] ^ en_vector[6];
    end
end
always @(posedge clk) begin
    if (!rst_n) begin
        encode_out_0_32 <= 32'd0;
        encode_out_1_32 <= 32'd0;
        encode_out_2_32 <= 32'd0;
        encode_out_3_32 <= 32'd0;
    end 
	else begin
        encode_out_0_32 <= vector_0 ^ vector_1;
        encode_out_1_32 <= vector_0 ^ vector_1 ^ vector_2;
        encode_out_2_32 <= vector_0 ^ vector_1 ^ vector_3;
        encode_out_3_32 <= vector_0 ^ vector_1 ^ vector_4;
    end
end
assign encode_out = {encode_out_3_32, encode_out_2_32, encode_out_1_32, encode_out_0_32};
// ====================================================================
// 输出有效信号流水线
// byte_vld 延迟两拍，使 out_vld 与数据路径的三级流水对齐
// 数据路径延迟：en_vector(1拍) -> vector(2拍) -> encode_out(3拍)
// 因此 out_vld 在 byte_vld 有效后的第3个时钟沿置起
// ====================================================================
reg				byte_vld_dly;
reg				byte_vld_2dly;

always @(posedge clk) begin
	if (!rst_n)begin
		byte_vld_dly <= 1'b0;
		byte_vld_2dly <= 1'b0;
		out_vld <= 1'b0;
	end
	else begin
		byte_vld_dly <= byte_vld;
		byte_vld_2dly <= byte_vld_dly;
		out_vld <= byte_vld_2dly;
	end
end
   
endmodule
