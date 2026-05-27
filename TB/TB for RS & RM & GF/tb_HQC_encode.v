`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/05/25 18:08:59
// Design Name: 
// Module Name: tb_HQC_encode
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


`timescale 1ns / 1ps

module tb_HQC_encode();

    // 激励信号
    reg          clk;
    reg          rst_n;
    reg  [127:0] msg_in;
    reg          msg_in_vld;

    // 观测信号
    wire [383:0] encode_out; // 128 bits * MULTIPLICITY(3) = 384 bits
    wire         out_vld;
    wire         done;

    // 实例化 HQC 顶层编码器 (采用 HQC-128 参数)
    HQC_encode_top #(
        .PARAM_HQC(128)
    ) uut (
        .clk        (clk),
        .rst_n      (rst_n),
        .msg_in     (msg_in),
        .msg_in_vld (msg_in_vld),
        .encode_out (encode_out),
        .out_vld    (out_vld),
        .done       (done)
    );

    // 生成 100MHz 时钟
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // 监控与计数输出的有效字
    integer out_word_cnt = 0;
    always @(posedge clk) begin
        if (out_vld) begin
            out_word_cnt = out_word_cnt + 1;
            // 为了日志清晰，只打印输出字的最低 64 位 (即基础 RM 码的部分特征)
            $display("Time: %0t | Out_VLD #%0d | RM_Encode_Out[63:0]: 0x%h", 
                     $time, out_word_cnt, encode_out[63:0]);
        end
    end

    // 主测试流程
    initial begin
        // 1. 初始化
        rst_n = 0;
        msg_in = 0;
        msg_in_vld = 0;
        
        // 等待复位释放
        #100;
        rst_n = 1;
        #25;

        // 2. 注入 128-bit 测试明文数据 (16 Bytes)
        // HQC 采用高位先进的策略，明文最高字节为 0x12
        msg_in = 128'h12345678_9ABCDEF0_11223344_55667788;
        msg_in_vld = 1;
        
        #10; // 维持一个时钟周期的脉冲
        msg_in_vld = 0;

        $display("=========================================================");
        $display("Msg injected. Waiting for RS+RM pipeline encoding...");
        $display("=========================================================");

        // 3. 等待编码完成
        wait(done == 1'b1);
        
        $display("=========================================================");
        $display("Encoding Complete at time %0t!", $time);
        $display("Total Words Output: %0d", out_word_cnt);
        
        // 自动断言检查
        if (out_word_cnt == 46) begin
            $display("✅ TEST PASS: Output exactly 46 RM codewords (16 Msg + 30 Parity) for HQC-128!");
        end else begin
            $display("❌ TEST FAIL: Expected 46 outputs, but got %0d.", out_word_cnt);
        end
        $display("=========================================================");

        #100;
        $finish;
    end

endmodule
