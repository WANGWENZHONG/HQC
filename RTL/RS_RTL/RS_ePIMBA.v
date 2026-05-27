// RS 码 BM 译码算法模块
module RS_ePIMBA#(
    parameter   PARAM_HQC = 128,
    parameter   T        = (PARAM_HQC == 128)? 15:
                           (PARAM_HQC == 192)? 16:
                           (PARAM_HQC == 256)? 29 : 15,  // 纠错能力
    parameter   POLYNUM  = 2 * T + 1,                  // 多项式阶数
    parameter   DATAIN   = 2 * T * 8,                   // 输入数据位宽
    parameter   CNT_W   = 8                           // 计数器位宽（图中未显式定义，需根据实际补充）
)(
    input                       		clk,
    input                       		rst_n,
    input  [DATAIN - 1 : 0]     		synd,       // 伴随式输入
    input                       		synd_vld,   // 伴随式有效信号
    output reg 	[8*(T+1)-1:0]			lambda,     // 译码数据输出
	output reg  [8*T-1:0]  				omega_out, 
	output reg        [7:0]          	gamma,
	output reg    	  [5:0]          	z_cnt,             
	output reg        [7:0]          	L_sigma,   // 当前迭代长度
    output reg                  		out_vld    // 输出有效信号
);

//==================== 内部信号声明 ====================
reg        [7:0]          omegax    [0 : POLYNUM-1]; // 
reg        [7:0]          sitax     [0 : POLYNUM-1]; // 
wire       [7:0]          omega_ca  [0 : POLYNUM-2]; // 乘法器输出（omegax 项）
wire        [7:0]         sita_ca   [0 : POLYNUM-1]; // 乘法器输出（sitax 项）
wire       [7:0]          deta;                      // 差异值
reg        [7:0]          L_B;                       // 
reg        [CNT_W-1:0]    ca_cnt;                    // 迭代计数器
wire                      para_en;                   // 参数更新使能
reg                       in_vld;                    // 乘法器输入有效
wire                      gf_vld_vector	[0 : POLYNUM-2];// 乘法器输出有效
reg						  out_vld_pre;
wire					  gf_vld  = gf_vld_vector[0];

//==================== 多项式更新：omegax ====================
integer i;

always @(posedge clk) begin
    if (synd_vld) begin
        // 伴随式加载：初始化错误位置多项式
        for (i = 0; i < POLYNUM-1; i = i + 1) begin
            omegax[i] <= synd[8*i +: 8]; // 按字节拆分伴随式
        end
        omegax[POLYNUM-1] <= 8'd1;      // 最高次项系数固定为1
    end
    else if (gf_vld) begin
        // BM 迭代更新：omegax = omega_ca ^ sita_ca
        for (i = 0; i < POLYNUM-1; i = i + 1) begin
            omegax[i] <= omega_ca[i] ^ sita_ca[i];
        end
        omegax[POLYNUM-1] <= sita_ca[POLYNUM-1];
    end
end

//==================== 多项式更新：sitax ====================
always @(posedge clk) begin
    if (synd_vld) begin
        // 伴随式加载：初始化辅助多项式
        for (i = 0; i < POLYNUM-2; i = i + 1) begin
            sitax[i] <= synd[8*i +: 8];
        end
        sitax[POLYNUM-1] <= 8'd1;
        sitax[POLYNUM-2] <= 8'd0;
    end
    else if (para_en) begin
        for (i = 1; i < POLYNUM; i = i + 1) begin
            sitax[i-1] <= omegax[i];
        end
        sitax[POLYNUM-1] <= 8'd0;
		sitax[2*T-ca_cnt-2] <= 8'd0;
    end
    else if ((L_B == T-1) && (gf_vld)) begin
        // 迭代阶段：sitax 循环移位
        for (i = 1; i < POLYNUM; i = i + 1) begin
            sitax[i-1] <= sitax[i];
        end
        sitax[POLYNUM-1] <= 8'd0;
		sitax[2*T-ca_cnt-2] <= 8'd0;
    end
	else if(gf_vld)
		sitax[2*T-ca_cnt-2] <= 8'd0;
end

//==================== 迭代计数器 ====================
always @(posedge clk) begin
    if (!rst_n)
		ca_cnt <= 'd0;
	else if (synd_vld)
        ca_cnt <= 'd0;          // 伴随式有效时复位计数器
    else if (gf_vld)
        ca_cnt <= ca_cnt + 1'b1; // 乘法器有效时计数+1
end

//==================== 乘法器实例化（GF(2^8)） ====================
// 为 omegax 生成乘法器
genvar j;
generate
    for (j = 1; j < POLYNUM; j = j + 1) begin : gen_omega_mult
        gf_mul_pipline_4 u_gf_mult_omega(
            .clk        (clk),
            .rst_n      (rst_n),
            .in_1       (omegax[j]),
            .in_2       (gamma),
            .start      (in_vld),
            .out        (omega_ca[j-1]),
            .done    	(gf_vld_vector[j-1])
        );
    end
endgenerate

// 为 sitax 生成乘法器
genvar k;
generate
    for (k = 0; k < POLYNUM; k = k + 1) begin : gen_sita_mult
        gf_mul_pipline_4 u_gf_mult_sita(
            .clk        (clk),
            .rst_n      (rst_n),
            .in_1       (sitax[k]),
            .in_2       (deta),
			.start      (in_vld),
            .out        (sita_ca[k]),
            .done    	() 
        );
    end
endgenerate

//==================== 使能信号控制 ====================
// 参数更新使能 para_en

assign    para_en = (deta != 8'd0) && (L_sigma <= L_B) && gf_vld;

// 乘法器输入有效 in_vld
always @(posedge clk) begin
    in_vld <= (gf_vld | synd_vld)&&((ca_cnt != 2*T-1));
end

//==================== BM 算法参数更新 ====================
// 更新 L_sigma
always @(posedge clk) begin
    if (!rst_n)
		L_sigma <= 8'd0;
	else if (synd_vld)
        L_sigma <= 8'd0;
    else if (para_en)
        L_sigma <= L_B + 1'b1;
end

// 更新 L_B
always @(posedge clk) begin
    if (!rst_n)
		L_B <= 8'd0;   
	else if (synd_vld)
        L_B <= 8'd0;
    else if (para_en)
        L_B <= L_sigma;
    else if ((L_B != T-1) && (gf_vld))
        L_B <= L_B + 1'b1;
end

// 更新 gamma
always @(posedge clk) begin
    if (!rst_n)
		gamma <= 8'd0;
    else if (synd_vld)
        gamma <= 8'd1;
    else if (para_en) 
        gamma <= deta;
end
//更新Z计数器（这里只计算更新了多少次Z，具体Z值在错误计算模块查表给出）
always @(posedge clk) begin
    if (!rst_n)
		z_cnt <= 'd0;
	else if (synd_vld)
        z_cnt <= 'd0;
    else if (para_en||(L_B != T-1)&&gf_vld)
        z_cnt <= z_cnt + 1'b1;
end

assign deta = omegax[0];
//==================== 输出信号 ====================
always @(posedge clk) begin
	if (!rst_n)begin
	    for (i = 0; i < T; i = i + 1)begin
            omega_out[i*8 +: 8] <= 8'd0;
		end	
	end
    if (out_vld_pre) begin
        for (i = 0; i < T; i = i + 1)begin
            omega_out[i*8 +: 8] <= sitax[i];
		end
    end
end

always @(posedge clk) begin
	if (!rst_n)begin
	    for (i = 0; i < T+1; i = i + 1)begin
            lambda[i*8 +: 8] <= 8'd0;
		end	
	end
    else if (out_vld_pre) begin
        for (i = 0; i < T+1; i = i + 1)begin
            lambda[i*8 +: 8] <= omegax[i];
		end
    end
end

//输出使能信号
always @(posedge clk) begin
    if((ca_cnt == 2*T-1)&&(gf_vld))
		out_vld_pre <= 1'b1;
	else
		out_vld_pre <= 1'b0;
end

always @(posedge clk) begin
    out_vld <= out_vld_pre;
end

endmodule
