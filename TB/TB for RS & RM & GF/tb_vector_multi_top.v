`timescale 1ns / 1ps
module tb_vector_multi_top();

    reg clk;
    reg rst_n;
    
    reg [127:0] poly_in;
    reg         poly_vld;
    reg         poly_in_last;
    
    reg [15*65-1:0] nonzero_index;
    reg             index_vld;
    
    wire [127:0] poly_out;
    wire         out_vld;

    // 实例化顶层
    vector_multi_top uut (
        .clk            (clk),
        .rst_n          (rst_n),
        .poly_in        (poly_in),
        .poly_vld       (poly_vld),
        .poly_in_last   (poly_in_last),
        .nonzero_index  (nonzero_index),
        .index_vld      (index_vld),
        .poly_out       (poly_out),
        .out_vld        (out_vld)
    );

    // 时钟生成 100MHz
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // 仿真激励
    integer i;
    initial begin
        // 1. 初始化
        rst_n = 0;
        poly_in = 0;
        poly_vld = 0;
        poly_in_last = 0;
        nonzero_index = 0;
        index_vld = 0;
        
        #100;
        rst_n = 1;
        #2000; // 等待内部上电自动清空 RAM 完成 (约 277 个周期)
        
        // 2. 灌入 70 个稀疏坐标 (模拟随意写入几个偏移量)
        for (i = 0; i < 65; i = i + 1) begin
            // 简单的等差数列测试
            nonzero_index[15*i +: 15] = i+64; 
        end
		@(posedge clk);
        index_vld = 1;
        #1;
		@(posedge clk);
        index_vld = 0;
        // 3. 灌入 139 个稠密多项式数据
        for (i = 0; i < 139
		; i = i + 1) begin
			@(posedge clk);
			#1
            poly_vld = 1;
            poly_in = {4{i[31:0]}}; // 造一些伪随机特征数据
            if (i == 138)begin
				poly_in_last = 1;
				poly_in = 128'd0;
			end
            else poly_in_last = 0;
            #5;
        end
		@(posedge clk);
        poly_vld = 0;
        poly_in_last = 0;
        
        // 4. 静静等待计算完成并观察 poly_out 的输出
        // 预计等待 139 * 34 = 约 4726 拍
        wait(out_vld == 1);
        $display("Output started at time %0t", $time);
        
        wait(out_vld == 0);
        $display("Output finished at time %0t", $time);
        
        #500;
        $finish;
    end

endmodule
