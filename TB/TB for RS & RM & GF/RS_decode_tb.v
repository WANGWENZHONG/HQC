`timescale 1ns / 1ps

module tb_hqc_rs_codec();

    // ==========================================
    // 1. 参数定义 (以 HQC-128 为例)
    // ==========================================
    parameter PARAM_HQC = 128;
    parameter PARAM_N1  = 46;
    parameter PARAM_K   = 16;
    parameter MSG_W     = 8 * PARAM_K;

    reg clk;
    reg rst_n;

    // ==========================================
    // 2. 编码器 (Encoder) 信号
    // ==========================================
    reg  [MSG_W-1:0]    enc_msg_in;
    reg                 enc_msg_in_vld;
    wire                enc_msg_out_vld;
    wire [7:0]          enc_msg_out;
    wire                enc_done;

    RS_encode #(
        .PARAM_HQC(PARAM_HQC)
    ) u_RS_encode (
        .clk            (clk),
        .rst_n          (rst_n),
        .msg_in         (enc_msg_in),
        .msg_in_vld     (enc_msg_in_vld),
        .msg_out_vld    (enc_msg_out_vld),
        .msg_out        (enc_msg_out),
        .done           (enc_done)
    );

    // ==========================================
    // 3. 译码器 (Decoder) 信号
    // ==========================================
    reg  [7:0]          dec_din;
    reg                 dec_din_valid;
    wire [MSG_W-1:0]    dec_msg_out;
    wire                dec_done;
    wire                dec_din_ready;

    RS_decode_top #(
        .PARAM_HQC(PARAM_HQC)
    ) u_RS_decode_top (
        .clk            (clk),
        .rst_n          (rst_n),
        .din            (dec_din),
        .din_valid      (dec_din_valid),
        .msg_out        (dec_msg_out),
        .done           (dec_done),
        .din_ready      (dec_din_ready)
    );

    // ==========================================
    // 时钟生成 (200MHz)
    // ==========================================
    initial begin
        clk = 0;
        forever #2.5 clk = ~clk;
    end

    // 用来暂存编码器吐出的 46 字节码字
    reg [7:0] codeword [0:PARAM_N1-1];
    integer i;
    integer enc_byte_cnt;

    // ==========================================
    // 4. 核心自动化测试流程
    // ==========================================
    initial begin
        // --- 初始化 ---
        rst_n = 0;
        enc_msg_in = 0;
        enc_msg_in_vld = 0;
        dec_din = 0;
        dec_din_valid = 0;
        enc_byte_cnt = PARAM_N1;

        #30 rst_n = 1;
        #20;
		@(posedge clk);
        // --- 步骤 A：喂给编码器原始消息 ---
        $display("\n==================================================");
        $display("[%0t] 步骤A：启动 RS 编码", $time);
        enc_msg_in = 128'h01020304_05060708_090A0B0C_0D0E0F10; // 测试用 16 字节随机消息
        enc_msg_in_vld = 1;
        @(posedge clk);
        enc_msg_in_vld = 0;

        // --- 步骤 B：捕获编码器的完整输出 ---
        fork
            begin
                while (enc_byte_cnt > 0) begin
                    @(posedge clk);
                    if (enc_msg_out_vld) begin
                        codeword[enc_byte_cnt-1] = enc_msg_out;
                        enc_byte_cnt = enc_byte_cnt - 1;
                    end
                end
            end
            begin
                wait(enc_done == 1'b1);
            end
        join
        $display("[%0t] 编码完成！成功捕获 %0d 字节码字。", $time, enc_byte_cnt);

        // --- 步骤 C：模拟信道，注入突发错误 ---
        // HQC-128 的 T=15，我们在这里随意翻转 5 个字节（不超过纠错极限）
        $display("\n==================================================");
        $display("[%0t] 步骤C：信道恶化，注入 5 个字节的错误...", $time);
        codeword[5]  = codeword[5]  ^ 8'hA5; // 错误 1 (消息区)
        codeword[12] = codeword[12] ^ 8'h3C; // 错误 2 (消息区)
        codeword[20] = codeword[20] ^ 8'hFF; // 错误 3 (校验区)
        codeword[35] = codeword[35] ^ 8'h11; // 错误 4 (校验区)
        codeword[45] = codeword[45] ^ 8'h77; // 错误 5 (校验区)

        #50;

        // --- 步骤 D：喂给译码器 ---
        $display("\n==================================================");
        $display("[%0t] 步骤D：启动 RS 译码，串行送入含错码字", $time);
        for (i = 0; i < PARAM_N1; i = i + 1) begin
            // 握手：确保接收端 Ready
			@(posedge clk);
			dec_din_valid = 1'b0;
            wait(dec_din_ready == 1'b1);
            @(posedge clk);
            dec_din = codeword[i];
            dec_din_valid = 1'b1;
        end
        @(posedge clk);
        dec_din_valid = 1'b0;

        // --- 步骤 E：等待译码完成 ---
        $display("[%0t] 码字发送完毕，等待硬件译码核心处理...", $time);
        wait(dec_done == 1'b1);
        $display("[%0t] 译码完成！", $time);

        // --- 步骤 F：结果自动比对 ---
        #20;
        $display("\n================= 最终结果校验 =================");
        $display("原始发送消息 : %h", enc_msg_in);
        $display("硬件纠错消息 : %h", dec_msg_out);

        if (dec_msg_out === enc_msg_in)
            $display("\n>>>> [ 测试通过 PASS ] 编码与译码结果完全一致！ <<<<\n");
        else
            $display("\n>>>> [ 测试失败 FAIL ] 数据存在差异，请检查波形！ <<<<\n");

        #100 $finish;
    end

    // 导出波形文件
    initial begin
        $dumpfile("hqc_rs_codec.vcd");
        $dumpvars(0, tb_hqc_rs_codec);
    end

endmodule