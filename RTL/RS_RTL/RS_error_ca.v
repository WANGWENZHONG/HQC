// ============================================================
//  rs_csee_semi_parallel.v
//  半并行 Chien Search & Error Evaluation (内层并行，外层串行)
// ============================================================
module RS_error_ca#(
    parameter PARAM_HQC = 128,
    parameter T		   = (PARAM_HQC == 128) ? 15 :
                         (PARAM_HQC == 192) ? 16 :
                         (PARAM_HQC == 256) ? 29 : 15,
    parameter PARAM_N1 = (PARAM_HQC == 128) ? 46 :
                         (PARAM_HQC == 192) ? 56 :
                         (PARAM_HQC == 256) ? 90 : 46,
    parameter PARAM_K  = (PARAM_HQC == 128) ? 16 :
                         (PARAM_HQC == 192) ? 24 :
                         (PARAM_HQC == 256) ? 32 : 16,
    parameter CNT_W    = (PARAM_HQC == 256) ? 7 : 6
)(
    input                        clk,
    input                        rst_n,
    input                        data_vld,
    input  [8*(T+1)-1:0]         lambda,
    input  [8*T-1:0]             omega,
    input  [7:0]                 gamma,
	input  [7:0]                 L_sigma,
    input  [5:0]                 z_cnt,
	input						 msg_vld,
    input  [8*PARAM_K-1:0]       msg_in,

    output reg [8*PARAM_K-1:0]   msg_out,
    output reg                   done
);


reg			[7:0]         		 lambda_reg [0:T];
reg			[7:0]         		 omega_reg [0:T-1];
reg			[39:0]		  	   	 z_reg;
reg			[7:0]		  	   	 Z;
reg			[7:0]		  	   	 in_change;

wire							chein_mul_vld_vector [0:T-1];
reg								chein_gf_vld;
wire							chein_mul_vld = chein_mul_vld_vector[0];

reg			[CNT_W-1 :0]		chein_gf_cnt;
reg			[CNT_W-1 :0]		error_cnt;

wire		[7:0]        	 	lambda_mul [0:T-1];
wire		[7:0]       	  	omega_mul [0:T-2];

reg		    [8*T-1:0]			alpha_inv_row;//alpha^i^j逆元
reg		    [7:0]				inv_denom;
//==================== 控制信号 ====================
reg								data_vld_dly;
reg								data_vld_2dly;

always @(posedge clk)begin
	data_vld_dly <= data_vld;
end

always @(posedge clk)begin
	data_vld_2dly <= data_vld_dly;
end


//==================== 数据缓存 ====================
 
integer k;
 
always @(posedge clk)begin
	if (!rst_n)begin
	    for (k = 0; k < T+1; k = k + 1)begin
            lambda_reg[k] <= 8'd0;
		end	
	end
    else if (data_vld)begin
	    for (k = 0; k < T+1; k = k + 1) begin
            lambda_reg[k] <= lambda[8*k +: 8]; // 按字节拆分
        end
	end
end

integer l;

always @(posedge clk)begin
	if (!rst_n)begin
	    for (l = 0; l < T; l = l + 1)begin
            omega_reg[l] <= 8'd0;
		end	
	end
    else if (data_vld)begin
	    for (l = 0; l < T; l = l + 1) begin
            omega_reg[l] <= omega[8*l +: 8]; // 按字节拆分
        end
	end
end


//==================== 钱搜索乘法器 ====================
genvar i;
generate
	for (i = 0; i < T; i = i+1)begin
		gf_mul_pipline_4 	lambda_gf (
			.clk  			(clk),
			.rst_n			(rst_n),
			.start			(chein_gf_vld),
			.in_1 			(lambda_reg[i+1]),
			.in_2 			(alpha_inv_row[i*8+:8]),
			.out  			(lambda_mul[i]),
			.done 			(chein_mul_vld_vector[i])
		);
	end
endgenerate
//====================钱搜索计数器 ====================
always @(posedge clk)begin
	if (!rst_n)
		chein_gf_cnt <= 'd0;
	else if (data_vld)
		chein_gf_cnt <= z_cnt;
	else if (data_vld_dly)
		chein_gf_cnt <= 'd0;	
	else if (chein_gf_vld||data_vld_2dly)
		chein_gf_cnt <= chein_gf_cnt + 1'b1;
	
end

//==================== 钱搜索使能信号 ====================
always @(posedge clk)begin
	if(!rst_n)
		chein_gf_vld <= 1'b0;
	else if (data_vld_2dly)
		chein_gf_vld <= 1'b1;
	else if (chein_gf_cnt == PARAM_N1)
		chein_gf_vld <= 1'b0;
	
end

//==================== lambda多项式求和 ====================
reg [7:0] lambda_sum_odd;
reg [7:0] lambda_sum_odd_dly;
reg [7:0] lambda_sum_even;
reg [7:0] lambda_sum;
reg		  sum_vld;
reg		  sum_vld_pre;
generate 
	if (T == 15)begin
		reg [7:0] lambda_sum_odd_0;
		reg [7:0] lambda_sum_even_0;
		reg [7:0] lambda_sum_odd_1;
		reg [7:0] lambda_sum_even_1;
		reg		  sum_vld_2pre;
		always @(posedge clk) begin
			lambda_sum_odd_0 <= lambda_mul[0]^lambda_mul[2]^lambda_mul[4]^lambda_mul[6];
			lambda_sum_odd_1 <= lambda_mul[8]^lambda_mul[10]^lambda_mul[12]^lambda_mul[14];	
			lambda_sum_even_0 <= lambda_reg[0]^lambda_mul[1]^lambda_mul[3]^lambda_mul[5];
			lambda_sum_even_1 <= lambda_mul[7]^lambda_mul[9]^lambda_mul[11]^lambda_mul[13];
			sum_vld_2pre <= chein_mul_vld;
		end
	
		always @(posedge clk) begin
			lambda_sum_odd <= lambda_sum_odd_0^lambda_sum_odd_1;		
			lambda_sum_even <= lambda_sum_even_0^lambda_sum_even_1;	
			sum_vld_pre <= sum_vld_2pre;
		end
		
		always @(posedge clk) begin
			lambda_sum <= lambda_sum_even^lambda_sum_odd;
			sum_vld <= sum_vld_pre;
		end
	end	
	else if (T == 16)begin
		reg [7:0] lambda_sum_odd_0, lambda_sum_odd_1;
		reg [7:0] lambda_sum_even_0, lambda_sum_even_1;
		reg		  sum_vld_2pre;

		always @(posedge clk) begin
			lambda_sum_odd_0  <= lambda_mul[0] ^ lambda_mul[2] ^ lambda_mul[4] ^ lambda_mul[6];
			lambda_sum_odd_1  <= lambda_mul[8] ^ lambda_mul[10] ^ lambda_mul[12] ^ lambda_mul[14];
			lambda_sum_even_0 <= lambda_mul[1] ^ lambda_mul[3] ^ lambda_mul[5] ^ lambda_mul[7];
			lambda_sum_even_1 <= lambda_mul[9] ^ lambda_mul[11] ^ lambda_mul[13] ^ lambda_mul[15];
			sum_vld_2pre <= chein_gf_vld;
		end

		always @(posedge clk) begin
			lambda_sum_odd  <= lambda_sum_odd_0  ^ lambda_sum_odd_1;
			lambda_sum_even <= lambda_sum_even_0 ^ lambda_sum_even_1^lambda_reg[0];
			sum_vld_pre <= sum_vld_2pre;
		end

		always @(posedge clk) begin
			lambda_sum <= lambda_sum_even ^ lambda_sum_odd;
			sum_vld <= sum_vld_pre;
		end
	end
	else if (T == 29) begin
		// 第一级部分和：4 组奇数，4 组偶数
		reg [7:0] odd_grp0, odd_grp1, odd_grp2, odd_grp3;
		reg [7:0] even_grp0, even_grp1, even_grp2, even_grp3;
		// 第二级合并结果
		reg [7:0] odd_mid0, odd_mid1, even_mid0, even_mid1;
		// 第三级最终结果
		reg		  sum_vld_2pre;
		reg		  sum_vld_3pre;
		
		always @(posedge clk) begin
			odd_grp0 <= lambda_mul[0] ^ lambda_mul[2] ^ lambda_mul[4] ^ lambda_mul[6];
			odd_grp1 <= lambda_mul[8] ^ lambda_mul[10] ^ lambda_mul[12] ^ lambda_mul[14];
			odd_grp2 <= lambda_mul[16] ^ lambda_mul[18] ^ lambda_mul[20] ^ lambda_mul[22];
			odd_grp3 <= lambda_mul[24] ^ lambda_mul[26] ^ lambda_mul[28];           

			even_grp0 <= lambda_reg[0] ^ lambda_mul[1] ^ lambda_mul[3] ^ lambda_mul[5];
			even_grp1 <= lambda_mul[7] ^ lambda_mul[9] ^ lambda_mul[11] ^ lambda_mul[13];
			even_grp2 <= lambda_mul[15] ^ lambda_mul[17] ^ lambda_mul[19] ^ lambda_mul[21];
			even_grp3 <= lambda_mul[23] ^ lambda_mul[25] ^ lambda_mul[27];   
			sum_vld_3pre <= chein_gf_vld;
		end

		always @(posedge clk) begin
			odd_mid0  <= odd_grp0 ^ odd_grp1 ;
			odd_mid1  <= odd_grp2 ^ odd_grp3;
			even_mid0 <= even_grp0 ^ even_grp1;
			even_mid1 <= even_grp2 ^ even_grp3;
			sum_vld_2pre <= sum_vld_3pre;
		end

		always @(posedge clk) begin
			lambda_sum_odd  <= odd_mid0 ^ odd_mid1;
			lambda_sum_even <= even_mid0 ^ even_mid1;
			sum_vld_pre <= sum_vld_2pre;
		end
		
		always @(posedge clk) begin
			lambda_sum <= lambda_sum_even ^ lambda_sum_odd;
			sum_vld <= sum_vld_pre;
		end
	end		
	
endgenerate



//==================== Omega乘法器 ====================
genvar j;
generate
	for (j = 0; j < T-1; j = j+1)begin
		gf_mul_pipline_4 	omega_gf (
			.clk  			(clk),
			.rst_n			(rst_n),
			.start			(chein_gf_vld),
			.in_1 			(omega_reg[j+1]),
			.in_2 			(alpha_inv_row[j*8+:8]),
			.out  			(omega_mul[j]),
			.done 			()
		);
	end
endgenerate

//==================== Omega多项式求和 ====================
reg [7:0] omega_sum_odd;
reg [7:0] omega_sum_even;
reg [7:0] omega_sum;
generate 
	if (T == 15)begin
		reg [7:0] omega_sum_odd_0;
		reg [7:0] omega_sum_even_0;
		reg [7:0] omega_sum_odd_1;
		reg [7:0] omega_sum_even_1;
		always @(posedge clk) begin
			omega_sum_odd_0 <= omega_mul[0]^omega_mul[2]^omega_mul[4]^omega_mul[6];
			omega_sum_odd_1 <= omega_mul[8]^omega_mul[10]^omega_mul[12];	
			omega_sum_even_0 <= omega_reg[0]^omega_mul[1]^omega_mul[3]^omega_mul[5];
			omega_sum_even_1 <= omega_mul[7]^omega_mul[9]^omega_mul[11]^omega_mul[13];
		end
	
		always @(posedge clk) begin
			omega_sum_odd <= omega_sum_odd_0^omega_sum_odd_1;		
			omega_sum_even <= omega_sum_even_0^omega_sum_even_1;	
		end
		
		always @(posedge clk) begin
			omega_sum <= omega_sum_even^omega_sum_odd;
		end
	end	
	else if (T == 16)begin
		reg [7:0] omega_sum_odd_0, omega_sum_odd_1;
		reg [7:0] omega_sum_even_0, omega_sum_even_1;
		always @(posedge clk) begin
			omega_sum_odd_0  <= omega_mul[0] ^ omega_mul[2] ^ omega_mul[4] ^ omega_mul[6];
			omega_sum_odd_1  <= omega_mul[8] ^ omega_mul[10] ^ omega_mul[12]^ omega_mul[14];
			omega_sum_even_0 <= omega_mul[1] ^ omega_mul[3] ^ omega_mul[5] ^ omega_mul[7];
			omega_sum_even_1 <= omega_mul[9] ^ omega_mul[11] ^ omega_mul[13];
		end

		always @(posedge clk) begin
			omega_sum_odd  <= omega_sum_odd_0  ^ omega_sum_odd_1;
			omega_sum_even <= omega_sum_even_0 ^ omega_sum_even_1^omega_reg[0];
		end

		always @(posedge clk) begin
			omega_sum <= omega_sum_even ^ omega_sum_odd;
		end
	end
	else if (T == 29) begin
		reg [7:0] odd_grp4, odd_grp5, odd_grp6, odd_grp7;
		reg [7:0] even_grp4, even_grp5, even_grp6, even_grp7;
		reg [7:0] odd_mid2, odd_mid3, even_mid2, even_mid3;
		
		always @(posedge clk) begin
			odd_grp4 <= omega_mul[0] ^ omega_mul[2] ^ omega_mul[4] ^ omega_mul[6];
			odd_grp5 <= omega_mul[8] ^ omega_mul[10] ^ omega_mul[12] ^ omega_mul[14];
			odd_grp6 <= omega_mul[16] ^ omega_mul[18] ^ omega_mul[20] ^ omega_mul[22];
			odd_grp7 <= omega_mul[24] ^ omega_mul[26];           

			even_grp4 <= omega_reg[0] ^ omega_mul[1] ^ omega_mul[3] ^ omega_mul[5];
			even_grp5 <= omega_mul[7] ^ omega_mul[9] ^ omega_mul[11] ^ omega_mul[13];
			even_grp6 <= omega_mul[15] ^ omega_mul[17] ^ omega_mul[19] ^ omega_mul[21];
			even_grp7 <= omega_mul[23] ^ omega_mul[25] ^ omega_mul[27];   
		end

		always @(posedge clk) begin
			odd_mid2  <= odd_grp4 ^ odd_grp5 ;
			odd_mid3  <= odd_grp6 ^ odd_grp7;
			even_mid2 <= even_grp4 ^ even_grp5;
			even_mid3 <= even_grp6 ^ even_grp7;
		end

		always @(posedge clk) begin
			omega_sum_odd  <= odd_mid2 ^ odd_mid3;
			omega_sum_even <= even_mid2 ^ even_mid3;
		end
		
		always @(posedge clk) begin
			omega_sum <= omega_sum_even ^ omega_sum_odd;
		end	
	end
	
endgenerate

// ------------------------------------------------------------------
//  错误值计算
// ------------------------------------------------------------------
//==================== 错误位置寄存器 ====================
reg		[8:0]	error_decide;
			
always @(posedge clk) begin
    if (data_vld) 
        error_decide <= 9'd0;
    else if	((sum_vld)&&(lambda_sum == 8'd0))
		error_decide <= {error_decide[7:0],1'b1};
	else
		error_decide <= {error_decide[7:0],1'b0};
		
end

//==================== z_reg的获取 ====================
reg	sum_vld_dly;

always @(posedge clk) begin
    if (!rst_n)
		z_reg <= 40'd0;
	else if (data_vld_2dly) 
        z_reg <= alpha_inv_row[39:0];
    else if	((sum_vld)&&(z_reg[15:8]!=8'd0))
		z_reg <= {8'd0,z_reg[39:8]};
end
always @(posedge clk) begin
    sum_vld_dly <= sum_vld;
end

always @(posedge clk) begin
    if (!rst_n)
		Z <= 8'd0;
	else if (data_vld) 
        Z <= gamma;
    else if	(numerator_vld)
		Z <= numerator;
end

always @(posedge clk) begin
    if (data_vld) 
        in_change <= lambda[7:0];
    else
		in_change <= z_reg[7:0];
end

always @(posedge clk) begin
    lambda_sum_odd_dly <= lambda_sum_odd;
end

//==================== 错误值计算====================

wire [7:0] numerator;
wire [7:0] denominator;
wire [7:0] error_val;
reg	denominator_vld_dly;
//分子计算
gf_mul_pipline_4 	error_gf_0 (
	.clk  			(clk),
	.rst_n			(rst_n),
	.start			(sum_vld_dly||data_vld_dly),
	.in_1 			(in_change),
	.in_2 			(Z),
	.out  			(numerator),
	.done 			(numerator_vld)
);
//分母计算（比分子计算早一拍）
gf_mul_pipline_4 	error_gf_1 (
	.clk  			(clk),
	.rst_n			(rst_n),
	.start			(sum_vld),
	.in_1 			(omega_sum),
	.in_2 			(lambda_sum_odd_dly),
	.out  			(denominator),
	.done 			(denominator_vld)
);


always @(posedge clk) begin
    denominator_vld_dly <= denominator_vld;
end
//两式相除
gf_mul_pipline_4 	u_gfmul (
	.clk  			(clk),
	.rst_n			(rst_n),
	.start			(denominator_vld_dly),
	.in_1 			(Z),
	.in_2 			(inv_denom),
	.out  			(error_val),
	.done 			(error_val_vld)
);
//==================== 错误位置计数器 ====================

always @(posedge clk)begin
	if(!rst_n)
		error_cnt <= 'd0;
	else if (data_vld)
		error_cnt <= 'd0;
	else if (error_val_vld)
		error_cnt <= error_cnt + 1'b1;
	else
		error_cnt <= 'd0;
end

//==================== 错误纠正 ====================
wire in_msg_range = (error_cnt >= PARAM_N1 - PARAM_K) && (error_cnt < PARAM_N1);
wire [CNT_W-1:0] msg_idx = error_cnt - (PARAM_N1 - PARAM_K);

always @(posedge clk) begin
	if (!rst_n)
		msg_out <= 'd0;
    else if (msg_vld)
        msg_out <= msg_in;
	else if (error_val_vld&&error_decide[8]&&in_msg_range)
		msg_out[8*msg_idx+:8] <= msg_out[8*msg_idx+:8] ^ error_val;
		
end

//==================== 输出使能 ====================
always @(posedge clk) begin
    if (!rst_n)
        done  <= 1'b0;
    else if (error_cnt == PARAM_N1-1)
        done <= 1'b1;
	else
		done <= 1'b0;
end

//==================== 求逆查找表 ====================
always @(posedge clk) begin
        case (denominator)
			8'd0  :inv_denom<=8'd0  ;8'd1  :inv_denom<=8'd1  ;8'd2  :inv_denom<=8'd142;
			8'd3  :inv_denom<=8'd244;8'd4  :inv_denom<=8'd71 ;8'd5  :inv_denom<=8'd167;
			8'd6  :inv_denom<=8'd122;8'd7  :inv_denom<=8'd186;8'd8  :inv_denom<=8'd173;
			8'd9  :inv_denom<=8'd157;8'd10 :inv_denom<=8'd221;8'd11 :inv_denom<=8'd152;
			8'd12 :inv_denom<=8'd61 ;8'd13 :inv_denom<=8'd170;8'd14 :inv_denom<=8'd93 ;
			8'd15 :inv_denom<=8'd150;8'd16 :inv_denom<=8'd216;8'd17 :inv_denom<=8'd114;
			8'd18 :inv_denom<=8'd192;8'd19 :inv_denom<=8'd88 ;8'd20 :inv_denom<=8'd224;
			8'd21 :inv_denom<=8'd62 ;8'd22 :inv_denom<=8'd76 ;8'd23 :inv_denom<=8'd102;
			8'd24 :inv_denom<=8'd144;8'd25 :inv_denom<=8'd222;8'd26 :inv_denom<=8'd85 ;
			8'd27 :inv_denom<=8'd128;8'd28 :inv_denom<=8'd160;8'd29 :inv_denom<=8'd131;
			8'd30 :inv_denom<=8'd75 ;8'd31 :inv_denom<=8'd42 ;8'd32 :inv_denom<=8'd108;
			8'd33 :inv_denom<=8'd237;8'd34 :inv_denom<=8'd57 ;8'd35 :inv_denom<=8'd81 ;
			8'd36 :inv_denom<=8'd96 ;8'd37 :inv_denom<=8'd86 ;8'd38 :inv_denom<=8'd44 ;
			8'd39 :inv_denom<=8'd138;8'd40 :inv_denom<=8'd112;8'd41 :inv_denom<=8'd208;
			8'd42 :inv_denom<=8'd31 ;8'd43 :inv_denom<=8'd74 ;8'd44 :inv_denom<=8'd38 ;
			8'd45 :inv_denom<=8'd139;8'd46 :inv_denom<=8'd51 ;8'd47 :inv_denom<=8'd110;
			8'd48 :inv_denom<=8'd72 ;8'd49 :inv_denom<=8'd137;8'd50 :inv_denom<=8'd111;
			8'd51 :inv_denom<=8'd46 ;8'd52 :inv_denom<=8'd164;8'd53 :inv_denom<=8'd195;
			8'd54 :inv_denom<=8'd64 ;8'd55 :inv_denom<=8'd94 ;8'd56 :inv_denom<=8'd80 ;
			8'd57 :inv_denom<=8'd34 ;8'd58 :inv_denom<=8'd207;8'd59 :inv_denom<=8'd169;
			8'd60 :inv_denom<=8'd171;8'd61 :inv_denom<=8'd12 ;8'd62 :inv_denom<=8'd21 ;
			8'd63 :inv_denom<=8'd225;8'd64 :inv_denom<=8'd54 ;8'd65 :inv_denom<=8'd95 ;
			8'd66 :inv_denom<=8'd248;8'd67 :inv_denom<=8'd213;8'd68 :inv_denom<=8'd146;
			8'd69 :inv_denom<=8'd78 ;8'd70 :inv_denom<=8'd166;8'd71 :inv_denom<=8'd4  ;
			8'd72 :inv_denom<=8'd48 ;8'd73 :inv_denom<=8'd136;8'd74 :inv_denom<=8'd43 ;
			8'd75 :inv_denom<=8'd30 ;8'd76 :inv_denom<=8'd22 ;8'd77 :inv_denom<=8'd103;
			8'd78 :inv_denom<=8'd69 ;8'd79 :inv_denom<=8'd147;8'd80 :inv_denom<=8'd56 ;
			8'd81 :inv_denom<=8'd35 ;8'd82 :inv_denom<=8'd104;8'd83 :inv_denom<=8'd140;
			8'd84 :inv_denom<=8'd129;8'd85 :inv_denom<=8'd26 ;8'd86 :inv_denom<=8'd37 ;
			8'd87 :inv_denom<=8'd97 ;8'd88 :inv_denom<=8'd19 ;8'd89 :inv_denom<=8'd193;
			8'd90 :inv_denom<=8'd203;8'd91 :inv_denom<=8'd99 ;8'd92 :inv_denom<=8'd151;
			8'd93 :inv_denom<=8'd14 ;8'd94 :inv_denom<=8'd55 ;8'd95 :inv_denom<=8'd65 ;
			8'd96 :inv_denom<=8'd36 ;8'd97 :inv_denom<=8'd87 ;8'd98 :inv_denom<=8'd202;
			8'd99 :inv_denom<=8'd91 ;8'd100:inv_denom<=8'd185;8'd101:inv_denom<=8'd196;
			8'd102:inv_denom<=8'd23 ;8'd103:inv_denom<=8'd77 ;8'd104:inv_denom<=8'd82 ;
			8'd105:inv_denom<=8'd141;8'd106:inv_denom<=8'd239;8'd107:inv_denom<=8'd179;
			8'd108:inv_denom<=8'd32 ;8'd109:inv_denom<=8'd236;8'd110:inv_denom<=8'd47 ;
			8'd111:inv_denom<=8'd50 ;8'd112:inv_denom<=8'd40 ;8'd113:inv_denom<=8'd209;
			8'd114:inv_denom<=8'd17 ;8'd115:inv_denom<=8'd217;8'd116:inv_denom<=8'd233;
			8'd117:inv_denom<=8'd251;8'd118:inv_denom<=8'd218;8'd119:inv_denom<=8'd121;
			8'd120:inv_denom<=8'd219;8'd121:inv_denom<=8'd119;8'd122:inv_denom<=8'd6  ;
			8'd123:inv_denom<=8'd187;8'd124:inv_denom<=8'd132;8'd125:inv_denom<=8'd205;
			8'd126:inv_denom<=8'd254;8'd127:inv_denom<=8'd252;8'd128:inv_denom<=8'd27 ;
			8'd129:inv_denom<=8'd84 ;8'd130:inv_denom<=8'd161;8'd131:inv_denom<=8'd29 ;
			8'd132:inv_denom<=8'd124;8'd133:inv_denom<=8'd204;8'd134:inv_denom<=8'd228;
			8'd135:inv_denom<=8'd176;8'd136:inv_denom<=8'd73 ;8'd137:inv_denom<=8'd49 ;
			8'd138:inv_denom<=8'd39 ;8'd139:inv_denom<=8'd45 ;8'd140:inv_denom<=8'd83 ;
			8'd141:inv_denom<=8'd105;8'd142:inv_denom<=8'd2  ;8'd143:inv_denom<=8'd245;
			8'd144:inv_denom<=8'd24 ;8'd145:inv_denom<=8'd223;8'd146:inv_denom<=8'd68 ;
			8'd147:inv_denom<=8'd79 ;8'd148:inv_denom<=8'd155;8'd149:inv_denom<=8'd188;
			8'd150:inv_denom<=8'd15 ;8'd151:inv_denom<=8'd92 ;8'd152:inv_denom<=8'd11 ;
			8'd153:inv_denom<=8'd220;8'd154:inv_denom<=8'd189;8'd155:inv_denom<=8'd148;
			8'd156:inv_denom<=8'd172;8'd157:inv_denom<=8'd9  ;8'd158:inv_denom<=8'd199;
			8'd159:inv_denom<=8'd162;8'd160:inv_denom<=8'd28 ;8'd161:inv_denom<=8'd130;
			8'd162:inv_denom<=8'd159;8'd163:inv_denom<=8'd198;8'd164:inv_denom<=8'd52 ;
			8'd165:inv_denom<=8'd194;8'd166:inv_denom<=8'd70 ;8'd167:inv_denom<=8'd5  ;
			8'd168:inv_denom<=8'd206;8'd169:inv_denom<=8'd59 ;8'd170:inv_denom<=8'd13 ;
			8'd171:inv_denom<=8'd60 ;8'd172:inv_denom<=8'd156;8'd173:inv_denom<=8'd8  ;
			8'd174:inv_denom<=8'd190;8'd175:inv_denom<=8'd183;8'd176:inv_denom<=8'd135;
			8'd177:inv_denom<=8'd229;8'd178:inv_denom<=8'd238;8'd179:inv_denom<=8'd107;
			8'd180:inv_denom<=8'd235;8'd181:inv_denom<=8'd242;8'd182:inv_denom<=8'd191;
			8'd183:inv_denom<=8'd175;8'd184:inv_denom<=8'd197;8'd185:inv_denom<=8'd100;
			8'd186:inv_denom<=8'd7  ;8'd187:inv_denom<=8'd123;8'd188:inv_denom<=8'd149;
			8'd189:inv_denom<=8'd154;8'd190:inv_denom<=8'd174;8'd191:inv_denom<=8'd182;
			8'd192:inv_denom<=8'd18 ;8'd193:inv_denom<=8'd89 ;8'd194:inv_denom<=8'd165;
			8'd195:inv_denom<=8'd53 ;8'd196:inv_denom<=8'd101;8'd197:inv_denom<=8'd184;
			8'd198:inv_denom<=8'd163;8'd199:inv_denom<=8'd158;8'd200:inv_denom<=8'd210;
			8'd201:inv_denom<=8'd247;8'd202:inv_denom<=8'd98 ;8'd203:inv_denom<=8'd90 ;
			8'd204:inv_denom<=8'd133;8'd205:inv_denom<=8'd125;8'd206:inv_denom<=8'd168;
			8'd207:inv_denom<=8'd58 ;8'd208:inv_denom<=8'd41 ;8'd209:inv_denom<=8'd113;
			8'd210:inv_denom<=8'd200;8'd211:inv_denom<=8'd246;8'd212:inv_denom<=8'd249;
			8'd213:inv_denom<=8'd67 ;8'd214:inv_denom<=8'd215;8'd215:inv_denom<=8'd214;
			8'd216:inv_denom<=8'd16 ;8'd217:inv_denom<=8'd115;8'd218:inv_denom<=8'd118;
			8'd219:inv_denom<=8'd120;8'd220:inv_denom<=8'd153;8'd221:inv_denom<=8'd10 ;
			8'd222:inv_denom<=8'd25 ;8'd223:inv_denom<=8'd145;8'd224:inv_denom<=8'd20 ;
			8'd225:inv_denom<=8'd63 ;8'd226:inv_denom<=8'd230;8'd227:inv_denom<=8'd240;
			8'd228:inv_denom<=8'd134;8'd229:inv_denom<=8'd177;8'd230:inv_denom<=8'd226;
			8'd231:inv_denom<=8'd241;8'd232:inv_denom<=8'd250;8'd233:inv_denom<=8'd116;
			8'd234:inv_denom<=8'd243;8'd235:inv_denom<=8'd180;8'd236:inv_denom<=8'd109;
			8'd237:inv_denom<=8'd33 ;8'd238:inv_denom<=8'd178;8'd239:inv_denom<=8'd106;
			8'd240:inv_denom<=8'd227;8'd241:inv_denom<=8'd231;8'd242:inv_denom<=8'd181;
			8'd243:inv_denom<=8'd234;8'd244:inv_denom<=8'd3  ;8'd245:inv_denom<=8'd143;
			8'd246:inv_denom<=8'd211;8'd247:inv_denom<=8'd201;8'd248:inv_denom<=8'd66 ;
			8'd249:inv_denom<=8'd212;8'd250:inv_denom<=8'd232;8'd251:inv_denom<=8'd117;
			8'd252:inv_denom<=8'd127;8'd253:inv_denom<=8'd255;8'd254:inv_denom<=8'd126;
			8'd255:inv_denom<=8'd253;
        default: inv_denom <= 8'd0;
	endcase
end



//==================== alpha^i^j逆元查找表 ====================
generate
if (PARAM_HQC == 128) begin
    always @(posedge clk) begin
        case (chein_gf_cnt)
            6'd0 : alpha_inv_row <= 120'h010101010101010101010101010101;
            6'd1 : alpha_inv_row <= 120'h2C58B07DFAE9CF831B366CD8AD478E;
            6'd2 : alpha_inv_row <= 120'h24907AF5F3EB8B16587DE98336D847;
            6'd3 : alpha_inv_row <= 120'h59F2C3568A243DF5FB8B2C7DCF36AD;
            6'd4 : alpha_inv_row <= 120'h640EE0A6B2EF560990F5EB167D83D8;
            6'd5 : alpha_inv_row <= 120'h9637AE641CA759EFAC24F4EB2CE96C;
            6'd6 : alpha_inv_row <= 120'h91B3DBC4576438A6F25624F58B7D36;
            6'd7 : alpha_inv_row <= 120'h55D5C6B3AB37820E53F2AC90FB581B;
            6'd8 : alpha_inv_row <= 120'hA954AA737EFFC4410EA6EF09F51683;
            6'd9 : alpha_inv_row <= 120'h3B172129E491F1C4823859563D8BCF;
            6'd10: alpha_inv_row <= 120'h1A7C33A94D7291FF3764A7EF24EBE9;
            6'd11: alpha_inv_row <= 120'hDF2281C5DA4DE47EAB571CB28AF3FA;
            6'd12: alpha_inv_row <= 120'h0F7F86CEC5A92973B3C464A656F57D;
            6'd13: alpha_inv_row <= 120'hB9CAB186813321AAC6DBAEE0C37AB0;
            6'd14: alpha_inv_row <= 120'hC1D2CA7F227C1754D5B3370EF29058;
            6'd15: alpha_inv_row <= 120'h60C1B90FDF1A3BA95591966459242C;
            6'd16: alpha_inv_row <= 120'h26C023A1F0E2CECC5473FF41A60916;
            6'd17: alpha_inv_row <= 120'h01984E0A99D644934F92D7DCDD450B;
            6'd18: alpha_inv_row <= 120'h2C087535BA0FB6CE172991C438568B;
            6'd19: alpha_inv_row <= 120'h24FA1D0C9FBE6B88EC15E64B079BCB;
            6'd20: alpha_inv_row <= 120'h59F46C269CA00FE27CA972FF64EFEB;
            6'd21: alpha_inv_row <= 120'h64C38B088FC1617FD01755B382F2FB;
            6'd22: alpha_inv_row <= 120'h967012CF879CBAF022C54D7E57B2F3;
            6'd23: alpha_inv_row <= 120'h91A5B2FB040346BC71ED84636EA2F7;
            6'd24: alpha_inv_row <= 120'h55F1078ACF2635A17FCEA973C4A6F5;
            6'd25: alpha_inv_row <= 120'hA9E63759EB2060A0FD1A2E7296A7F4;
            6'd26: alpha_inv_row <= 120'h3B9A7B07126C7523CA8633AADBE07A;
            6'd27: alpha_inv_row <= 120'h1AB8736EF22CCD3561B63B29F1383D;
            6'd28: alpha_inv_row <= 120'hDFC79AF170F408C0D27F7C54B30E90;
            6'd29: alpha_inv_row <= 120'h0F0D6DBF41AC36C914E76742FC8D48;
            6'd30: alpha_inv_row <= 120'hB9DF3B5596592C26C10F1AA9916424;
            6'd31: alpha_inv_row <= 120'hC11E6821E51CF580942F115CBF1912;
            6'd32: alpha_inv_row <= 120'h60DE7166B7AE8A8EC0A1E2CC734109;
            6'd33: alpha_inv_row <= 120'h2646E73E2996F2CF8FBADFC5E4578A;
            6'd34: alpha_inv_row <= 120'h014E99444FD7DD0B980AD69392DC45;
            6'd35: alpha_inv_row <= 120'h2CB4A0DF33E664F474C1FD7C5537AC;
            6'd36: alpha_inv_row <= 120'h2440B5783E556E8A08350FCE29C456;
            6'd37: alpha_inv_row <= 120'h598330618884DBF9D8275E68A8312B;
            6'd38: alpha_inv_row <= 120'h64F34C505B2EFC53FA0CBE88154B9B;
            6'd39: alpha_inv_row <= 120'h965608B5E73B73078B75B98621DBC3;
            6'd40: alpha_inv_row <= 120'h91A7E9605E6755AEF426A0E2A9FFEF;
            6'd41: alpha_inv_row <= 120'h5541F72DD2111562093A05A3B8F6F9;
            6'd42: alpha_inv_row <= 120'hA9DB564046DFB8F1C308C17F17B3F2;
            6'd43: alpha_inv_row <= 120'h3B6353364AFDC53FA2AD6ABB66E579;
            6'd44: alpha_inv_row <= 120'h1AA4198B065E3EB770CF9CF0C57EB2;
            6'd45: alpha_inv_row <= 120'hDFA9962426B91A55642C600F3B9159;
            default: alpha_inv_row <= 120'h010101010101010101010101010101;
        endcase
    end
end
else if (PARAM_HQC == 192) begin
	always @(posedge clk) begin
		case (chein_gf_cnt)
			6'd 0: alpha_inv_row <= 128'h01010101010101010101010101010101;
			6'd 1: alpha_inv_row <= 128'h162C58B07DFAE9CF831B366CD8AD478E;
			6'd 2: alpha_inv_row <= 128'h0924907AF5F3EB8B16587DE98336D847;
			6'd 3: alpha_inv_row <= 128'hA659F2C3568A243DF5FB8B2C7DCF36AD;
			6'd 4: alpha_inv_row <= 128'h41640EE0A6B2EF560990F5EB167D83D8;
			6'd 5: alpha_inv_row <= 128'hFF9637AE641CA759EFAC24F4EB2CE96C;
			6'd 6: alpha_inv_row <= 128'h7391B3DBC4576438A6F25624F58B7D36;
			6'd 7: alpha_inv_row <= 128'h5455D5C6B3AB37820E53F2AC90FB581B;
			6'd 8: alpha_inv_row <= 128'hCCA954AA737EFFC4410EA6EF09F51683;
			6'd 9: alpha_inv_row <= 128'hCE3B172129E491F1C4823859563D8BCF;
			6'd10: alpha_inv_row <= 128'hE21A7C33A94D7291FF3764A7EF24EBE9;
			6'd11: alpha_inv_row <= 128'hF0DF2281C5DA4DE47EAB571CB28AF3FA;
			6'd12: alpha_inv_row <= 128'hA10F7F86CEC5A92973B3C464A656F57D;
			6'd13: alpha_inv_row <= 128'h23B9CAB186813321AAC6DBAEE0C37AB0;
			6'd14: alpha_inv_row <= 128'hC0C1D2CA7F227C1754D5B3370EF29058;
			6'd15: alpha_inv_row <= 128'h2660C1B90FDF1A3BA95591966459242C;
			6'd16: alpha_inv_row <= 128'h8E26C023A1F0E2CECC5473FF41A60916;
			6'd17: alpha_inv_row <= 128'h0B01984E0A99D644934F92D7DCDD450B;
			6'd18: alpha_inv_row <= 128'h8A2C087535BA0FB6CE172991C438568B;
			6'd19: alpha_inv_row <= 128'h5324FA1D0C9FBE6B88EC15E64B079BCB;
			6'd20: alpha_inv_row <= 128'hAE59F46C269CA00FE27CA972FF64EFEB;
			6'd21: alpha_inv_row <= 128'hF164C38B088FC1617FD01755B382F2FB;
			6'd22: alpha_inv_row <= 128'hB7967012CF879CBAF022C54D7E57B2F3;
			6'd23: alpha_inv_row <= 128'h2A91A5B2FB040346BC71ED84636EA2F7;
			6'd24: alpha_inv_row <= 128'h6655F1078ACF2635A17FCEA973C4A6F5;
			6'd25: alpha_inv_row <= 128'h67A9E63759EB2060A0FD1A2E7296A7F4;
			6'd26: alpha_inv_row <= 128'h713B9A7B07126C7523CA8633AADBE07A;
			6'd27: alpha_inv_row <= 128'h781AB8736EF22CCD3561B63B29F1383D;
			6'd28: alpha_inv_row <= 128'hDEDFC79AF170F408C0D27F7C54B30E90;
			6'd29: alpha_inv_row <= 128'h9F0F0D6DBF41AC36C914E76742FC8D48;
			6'd30: alpha_inv_row <= 128'h60B9DF3B5596592C26C10F1AA9916424;
			6'd31: alpha_inv_row <= 128'h13C11E6821E51CF580942F115CBF1912;
			6'd32: alpha_inv_row <= 128'h4760DE7166B7AE8A8EC0A1E2CC734109;
			6'd33: alpha_inv_row <= 128'h8B2646E73E2996F2CF8FBADFC5E4578A;
			6'd34: alpha_inv_row <= 128'h45014E99444FD7DD0B980AD69392DC45;
			6'd35: alpha_inv_row <= 128'hA72CB4A0DF33E664F474C1FD7C5537AC;
			6'd36: alpha_inv_row <= 128'h572440B5783E556E8A08350FCE29C456;
			6'd37: alpha_inv_row <= 128'hF6598330618884DBF9D8275E68A8312B;
			6'd38: alpha_inv_row <= 128'hD564F34C505B2EFC53FA0CBE88154B9B;
			6'd39: alpha_inv_row <= 128'h15965608B5E73B73078B75B98621DBC3;
			6'd40: alpha_inv_row <= 128'h3391A7E9605E6755AEF426A0E2A9FFEF;
			6'd41: alpha_inv_row <= 128'hBD5541F72DD2111562093A05A3B8F6F9;
			6'd42: alpha_inv_row <= 128'hB6A9DB564046DFB8F1C308C17F17B3F2;
			6'd43: alpha_inv_row <= 128'h3C3B6353364AFDC53FA2AD6ABB66E579;
			6'd44: alpha_inv_row <= 128'h6F1AA4198B065E3EB770CF9CF0C57EB2;
			6'd45: alpha_inv_row <= 128'hC1DFA9962426B91A55642C600F3B9159;
			6'd46: alpha_inv_row <= 128'h300F767EF21005D92AA5FB03BCED63A2;
			6'd47: alpha_inv_row <= 128'h87B96839381B6A7FDA313DB4C23ED151;
			6'd48: alpha_inv_row <= 128'hADC1B615578B607866F18A26A1CE73A6;
			6'd49: alpha_inv_row <= 128'hCB60F085DB48B42FC77EC374D2D0D553;
			6'd50: alpha_inv_row <= 128'hAC26BE7C91EF74B967E65920A01A72A7;
			6'd51: alpha_inv_row <= 128'hDD010A4492DD010A4492DD010A4492DD;
			6'd52: alpha_inv_row <= 128'hA52C4AE11519E9B5719A076C2386AAE0;
			6'd53: alpha_inv_row <= 128'h7B24C91E1762EB27B14282E977D9A470;
			6'd54: alpha_inv_row <= 128'hE4593AA1EDB3248F78B86E2C35B62938;
			6'd55: alpha_inv_row <= 128'h84646C051AE6EF265E3396EB9CDF4D1C;
            default: alpha_inv_row <= 128'h01010101010101010101010101010101;
		endcase
	end
end
else if	(PARAM_HQC == 256) begin
	always @(posedge clk) begin
		case (chein_gf_cnt)
			7'd 0: alpha_inv_row <= 232'h0101010101010101010101010101010101010101010101010101010101;
			7'd 1: alpha_inv_row <= 232'h48903D7AF4F5F7F3FBEBCB8B0B162C58B07DFAE9CF831B366CD8AD478E;
			7'd 2: alpha_inv_row <= 232'h8D0E38E0A7A6A2B2F2EF9B56450924907AF5F3EB8B16587DE98336D847;
			7'd 3: alpha_inv_row <= 232'hFCB3F1DB96C46E5782640738DDA659F2C3568A243DF5FB8B2C7DCF36AD;
			7'd 4: alpha_inv_row <= 232'h425429AA7273637EB3FF4BC4DC41640EE0A6B2EF560990F5EB167D83D8;
			7'd 5: alpha_inv_row <= 232'h677C3B332EA9844D5572E691D7FF9637AE641CA759EFAC24F4EB2CE96C;
			7'd 6: alpha_inv_row <= 232'hE77FB6861ACEEDC517A91529927391B3DBC4576438A6F25624F58B7D36;
			7'd 7: alpha_inv_row <= 232'h14D261CAFD7F7122D07CEC174F5455D5C6B3AB37820E53F2AC90FB581B;
			7'd 8: alpha_inv_row <= 232'hC9C03523A0A1BCF07FE288CE93CCA954AA737EFFC4410EA6EF09F51683;
			7'd 9: alpha_inv_row <= 232'h3608CD75603546BA610F6BB644CE3B172129E491F1C4823859563D8BCF;
			7'd10: alpha_inv_row <= 232'hACF42C6C2026039CC1A0BE0FD6E21A7C33A94D7291FF3764A7EF24EBE9;
			7'd11: alpha_inv_row <= 232'h4170F212EBCF04878F9C9FBA99F0DF2281C5DA4DE47EAB571CB28AF3FA;
			7'd12: alpha_inv_row <= 232'hBFF16E07598AFBCF08260C350AA10F7F86CEC5A92973B3C464A656F57D;
			7'd13: alpha_inv_row <= 232'h6D9A737B3707B2128B6C1D754E23B9CAB186813321AAC6DBAEE0C37AB0;
			7'd14: alpha_inv_row <= 232'h0DC7B89AE6F1A570C3F4FA0898C0C1D2CA7F227C1754D5B3370EF29058;
			7'd15: alpha_inv_row <= 232'h0FDF1A3BA95591966459242C012660C1B90FDF1A3BA95591966459242C;
			7'd16: alpha_inv_row <= 232'h9FDE787167662AB7F1AE538A0B8E26C023A1F0E2CECC5473FF41A60916;
			7'd17: alpha_inv_row <= 232'h984E0A99D644934F92D7DCDD450B01984E0A99D644934F92D7DCDD450B;
			7'd18: alpha_inv_row <= 232'h7D408FB5B978D93EB855FC6EDD8A2C087535BA0FB6CE172991C438568B;
			7'd19: alpha_inv_row <= 232'hF9F3AD4C9C50CA5BCE2EA4FCDC5324FA1D0C9FBE6B88EC15E64B079BCB;
			7'd20: alpha_inv_row <= 232'h37A724E97460055EDF672E55D7AE59F46C269CA00FE27CA972FF64EFEB;
			7'd21: alpha_inv_row <= 232'hE4DB07562C400C462FDFCEB892F164C38B088FC1617FD01755B382F2FB;
			7'd22: alpha_inv_row <= 232'hCCA4B319EF8B1006465E5B3E4FB7967012CF879CBAF022C54D7E57B2F3;
			7'd23: alpha_inv_row <= 232'h4376A87EAEF2CB100C05CAD9932A91A5B2FB040346BC71ED84636EA2F7;
			7'd24: alpha_inv_row <= 232'h2FB6ED159157F28B40605078446655F1078ACF2635A17FCEA973C4A6F5;
			7'd25: alpha_inv_row <= 232'h6ABEDF7C8491AEEF2C749CB9D667A9E63759EB2060A0FD1A2E7296A7F4;
			7'd26: alpha_inv_row <= 232'hE84AA1E17C157E1956E94CB599713B9A7B07126C7523CA8633AADBE07A;
			7'd27: alpha_inv_row <= 232'h8B3A25A1DFEDA8B30724AD8F0A781AB8736EF22CCD3561B63B29F1383D;
			7'd28: alpha_inv_row <= 232'h51CB3A4ABEB676A4DBA7F3404EDEDFC79AF170F408C0D27F7C54B30E90;
			7'd29: alpha_inv_row <= 232'h4B518BE86A2F43CCE437F97D989F0F0D6DBF41AC36C914E76742FC8D48;
			7'd30: alpha_inv_row <= 232'h5596592C26C10F1AA99164240160B9DF3B5596592C26C10F1AA9916424;
			7'd31: alpha_inv_row <= 232'h7649C4F9E97514BB3E4DE3A60B13C11E6821E51CF580942F115CBF1912;
			7'd32: alpha_inv_row <= 232'h5B97E4A5ACAD306FB633D557454760DE7166B7AE8A8EC0A1E2CC734109;
			7'd33: alpha_inv_row <= 232'hA1D917BF643D4035651A21B3DD8B2646E73E2996F2CF8FBADFC5E4578A;
			7'd34: alpha_inv_row <= 232'h4E99444FD7DD0B980AD69392DC45014E99444FD7DD0B980AD69392DC45;
			7'd35: alpha_inv_row <= 232'h206A0F674D96EF6C60BE11A9D7A72CB4A0DF33E664F474C1FD7C5537AC;
			7'd36: alpha_inv_row <= 232'hF5CD466B3BE4823D3AC1E7ED92572440B5783E556E8A08350FCE29C456;
			7'd37: alpha_inv_row <= 232'h70167569E2B8E5537D03DE864FF6598330618884DBF9D8275E68A8312B;
			7'd38: alpha_inv_row <= 232'hF6B2369D5ED09A958A2077E793D564F34C505B2EFC53FA0CBE88154B9B;
			7'd39: alpha_inv_row <= 232'hA8C48A40C16BC5BF382C8FA14415965608B5E73B73078B75B98621DBC3;
			7'd40: alpha_inv_row <= 232'h7C7264EBB4B9118496AC20C1D63391A7E9605E6755AEF426A0E2A9FFEF;
			7'd41: alpha_inv_row <= 232'hB1CCFCA26C253CC7731C580C99BD5541F72DD2111562093A05A3B8F6F9;
			7'd42: alpha_inv_row <= 232'hBA8615C424CD50D921968A3A0AB6A9DB564046DFB8F1C308C17F17B3F2;
			7'd43: alpha_inv_row <= 232'h18BC3ED51C7DC089EDE6E0CF4E3C3B6353364AFDC53FA2AD6ABB66E579;
			7'd44: alpha_inv_row <= 232'h8E777F5CFF561D14D984953D986F1AA4198B065E3EB770CF9CF0C57EB2;
			7'd45: alpha_inv_row <= 232'h2426B91A55642C600F3B915901C1DFA9962426B91A55642C600F3B9159;
			7'd46: alpha_inv_row <= 232'hC8B027F033B39B1D50119A820B300F767EF21005D92AA5FB03BCED63A2;
			7'd47: alpha_inv_row <= 232'h7EF940281129325827FDCCF14587B96839381B6A7FDA313DB4C23ED151;
			7'd48: alpha_inv_row <= 232'h216EFB0C0FC5B356CDB9D0E4DDADC1B615578B607866F18A26A1CE73A6;
			7'd49: alpha_inv_row <= 232'hBDB7A6020586528DCF6AE121DCCB60F085DB48B42FC77EC374D2D0D553;
			7'd50: alpha_inv_row <= 232'hFD2E96F4030F33FF24B45E3BD7AC26BE7C91EF74B967E65920A01A72A7;
			7'd51: alpha_inv_row <= 232'h0A4492DD010A4492DD010A4492DD010A4492DD010A4492DD010A4492DD;
			7'd52: alpha_inv_row <= 232'hEA8966ABF40CF05CC4EB9D6B4FA52C4AE11519E9B5719A076C2386AAE0;
			7'd53: alpha_inv_row <= 232'h1B9F8649A7085DBDBFEF8761937B24C91E1762EB27B14282E977D9A470;
			7'd54: alpha_inv_row <= 232'h562D656696FB277F1564364644E4593AA1EDB3248F78B86E2C35B62938;
			7'd55: alpha_inv_row <= 232'hAEE9C111725974BE3BFFF460D684646C051AE6EF265E3396EB9CDF4D1C;
			7'd56: alpha_inv_row <= 232'hD19B2D892E6EB0778672B2CD999796CB4AB6A4A740DEC7F1F4C07F540E;
			7'd57: alpha_inv_row <= 232'hB857CF461ABF567578A982360AD0918A8FE72164AD50CEFC240C6B1507;
			7'd58: alpha_inv_row <= 232'h88D156EAFD21C88EBA7CF6F54E5B5551E82FCC377D9F0DBFACC9E7428D;
			7'd59: alpha_inv_row <= 232'h896D82D8A03EF6F725E239F2981EA93247BAF8FFFB94AFE4EF5A789EC8;
			7'd60: alpha_inv_row <= 232'hC11A912460DF5559260FA96401B93B962CC11A912460DF5559260FA964;
			7'd61: alpha_inv_row <= 232'h4C3C210E2061CCA536A0F8DB0BEE1A3F90277172C3EABBA8A7E8656D32;
			7'd62: alpha_inv_row <= 232'hB08CCEF6EBB50D3F3D9CAF734518DF49F975BB4DA6131E211C802F5C19;
			7'd63: alpha_inv_row <= 232'hF2756B29592DE7A8A6267815DDCD0F21383A65A907402FB86408611782;
			7'd64: alpha_inv_row <= 232'h951BBA76373669EC6E6CD2C5DCD8B997A5AD6F335747DE66AE8EA1CC41;
			7'd65: alpha_inv_row <= 232'h72AC60E2E6249C1191F46A1AD7EBC167FF2C057C96E9A03B376CB933AE;
			7'd66: alpha_inv_row <= 232'h6682082FA938CD78A859757F925660D9BF3D351AB38B463E96CFBAC557;
			7'd67: alpha_inv_row <= 232'hAFC6F57767DBFA5DC5AE042F4FE026D3A4C318E2BF7AD4D0FFB05076A5;
			7'd68: alpha_inv_row <= 232'h994FDD98D692454E44D70B0A93DC01994FDD98D692454E44D70B0A93DC;
			7'd69: alpha_inv_row <= 232'h35D0DBCFB91707CDE755562744B32C50C582400FA8F20CD991FB46ED6E;
			7'd70: alpha_inv_row <= 232'h74FD55AC9C1AFFE9B92E1C26D672246A67966CBEA9A7B4DFE6F4C17C37;
			7'd71: alpha_inv_row <= 232'hCB14C53274E74909356731AD99425906AFFC16A0668D876B7248B51F95;
			7'd72: alpha_inv_row <= 232'hA68FD9FC2CBA17382DDFBFFB0AC564CD6BE43DC1ED574078558A35CEC4;
			7'd73: alpha_inv_row <= 232'hABD82F2AEF27344BAD5E54C34E689647BCA89B9CD0318E654D2B25BD62;
			7'd74: alpha_inv_row <= 232'hA409B5F8AE3ABBD5F505970798A3911669B8530386F6836184F9276831;
			7'd75: alpha_inv_row <= 232'h3B6426DF912CB9A959601A96010F5524C13B6426DF912CB9A959601A96;
			7'd76: alpha_inv_row <= 232'hA37E7D5F84C34A1F5774B1BF0BD2A9B29DD09520E7D5F3502E530C884B;
			7'd77: alpha_inv_row <= 232'hDE42C3947C8213A3FCE9C2A845773B8D5AD9F66C65A4484633708F22AB;
			7'd78: alpha_inv_row <= 232'h27CE57CDDFFCCF2F29244666DD0C1AC4406BBF2CA11556B53B077586DB;
			7'd79: alpha_inv_row <= 232'h10BBBF58BEA8092366A730D0DCE8DFE51B65AAF4506D79257C322DAFE3;
			7'd80: alpha_inv_row <= 232'hF4A0A9EF6A3B1C031A3774DFD76C0F72EBB984ACC133A76067AE26E2FF;
			7'd81: alpha_inv_row <= 232'h380CD05726D9DB086B91CF6592FBB9158A46175925ED078F1A6ECDB6F1;
			7'd82: alpha_inv_row <= 232'h7B8EE763E96539CBA14D90504F2BC1CCA225C71C0CBD412D11623AA3F6;
			7'd83: alpha_inv_row <= 232'h5448509EAC465CF9B53351259370601FC88F68AE2D2295CDE2AB40E17B;
			7'd84: alpha_inv_row <= 232'h3E070CCE648FD082751A572D446E2686C4CDD9963AB6DB40DFF1087FB3;
			7'd85: alpha_inv_row <= 232'hD6D701D6D701D6D701D6D701D6D701D6D701D6D701D6D701D6D701D6D7;
			7'd86: alpha_inv_row <= 232'h5D2A3DD24DF5DE52FBBEAA8B99392CBCD57D89E6CF3C6336FD3FADBBE5;
			7'd87: alpha_inv_row <= 232'h0C3E38273BA63566F2C1B8560A2124BAA8F5A1558B2FE47D0FBF36E7FC;
			7'd88: alpha_inv_row <= 232'h47B1F180E2C44C0D82031F384EEC59775C5614843D6FA48B5EB7CFF07E;
			7'd89: alpha_inv_row <= 232'h126929CB5E731BD3B32071C498346430C7A6D42E56282AF5BE397D3C3F;
            default: alpha_inv_row <= 232'h0101010101010101010101010101010101010101010101010101010101;
		endcase
	end
end
endgenerate

















endmodule