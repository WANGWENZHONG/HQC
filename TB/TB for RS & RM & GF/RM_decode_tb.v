`timescale 1ns / 1ps

module RM_decode_tb();

    // =========================================================================
    // 全局时钟与复位
    // =========================================================================
    reg clk;
    reg rst_n;

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // 测试参数：快速验证 4 个字节的 RM 编译码
    localparam TEST_BYTES   = 4; 
    localparam MULTIPLICITY = 3; // HQC-128的RM重复次数

    // =========================================================================
    // [1] RM 编码器接口与实例化
    // =========================================================================
    reg  [7:0]   enc_byte_in;
    reg          enc_byte_vld;
    wire [127:0] enc_data_out;
    wire         enc_out_vld;

    RM_encode uut_enc (
        .clk        (clk),
        .rst_n      (rst_n),
        .byte_in    (enc_byte_in),
        .byte_vld   (enc_byte_vld),
        .encode_out (enc_data_out),
        .out_vld    (enc_out_vld)
    );

    // =========================================================================
    // [2] 仿真信道缓冲区 (存储编码输出，准备喂给解码器)
    // =========================================================================
    reg [127:0] encoded_buffer [0:TEST_BYTES-1];
    reg [7:0]   golden_bytes   [0:TEST_BYTES-1];
    integer enc_capture_cnt;

    always @(posedge clk) begin
        if (!rst_n) begin
            enc_capture_cnt <= 0;
        end else if (enc_out_vld && enc_capture_cnt < TEST_BYTES) begin
            encoded_buffer[enc_capture_cnt] <= enc_data_out;
            enc_capture_cnt <= enc_capture_cnt + 1;
        end
    end

    // =========================================================================
    // [3] RM 解码器接口与实例化
    // =========================================================================
    reg          dec_start;
    reg  [127:0] dec_data_in;
    reg          dec_data_in_vld;
    
    wire         dec_data_in_ready;
    wire [7:0]   dec_data_in_address; 
    
    wire         dec_out_vld;
    wire [7:0]   dec_out_data;
    wire [5:0]   dec_out_address;
    wire         dec_done;

    RM_decode_top #(
        .PARAM_HQC(128),
        .BYTE_NUM (TEST_BYTES) // 强制覆盖参数，仅测 4 字节以加快仿真
    ) uut_dec (
        .clk              (clk),
        .rst_n            (rst_n),
        .decode_start     (dec_start),
        .data_in          (dec_data_in),
        .data_in_vld      (dec_data_in_vld),
        .data_in_ready    (dec_data_in_ready),
        .data_in_address  (dec_data_in_address),
        .data_out_vld     (dec_out_vld),
        .data_out         (dec_out_data),
        .data_out_address (dec_out_address),
        .decode_done      (dec_done)
    );

    // =========================================================================
    // [4] 解码数据推送与【噪声注入】逻辑
    //     HQC 规定解码时，一个字节对应的 128-bit 要输入 MULTIPLICITY 次
    // =========================================================================
    integer dec_feed_byte_cnt;
    integer dec_feed_mult_cnt;

    always @(posedge clk) begin
        if (!rst_n) begin
            dec_data_in_vld   <= 0;
            dec_data_in       <= 0;
            dec_feed_byte_cnt <= 0;
            dec_feed_mult_cnt <= 0;
        end else if (dec_data_in_ready && enc_capture_cnt == TEST_BYTES && dec_feed_byte_cnt < TEST_BYTES) begin
            
            // 🔥 注入错误噪声：翻转最低 4 个 bit，测试 RM(1,7) 的抗干扰纠错能力！
            dec_data_in     <= encoded_buffer[dec_feed_byte_cnt] ^ 128'h0000000000000000000000000000000F;
            dec_data_in_vld <= 1;

            if (dec_feed_mult_cnt == MULTIPLICITY - 1) begin
                dec_feed_mult_cnt <= 0;
                dec_feed_byte_cnt <= dec_feed_byte_cnt + 1;
            end else begin
                dec_feed_mult_cnt <= dec_feed_mult_cnt + 1;
            end
        end else begin
            dec_data_in_vld <= 0;
        end
    end

    // =========================================================================
    // [5] 自动比对与校验
    // =========================================================================
    integer err_cnt = 0;
    always @(posedge clk) begin
        if (dec_out_vld) begin
            if (dec_out_data !== golden_bytes[dec_out_address]) begin
                $display("❌ 错误 [Byte %0d]: 解码结果=%h, 期望值(金标准)=%h", 
                         dec_out_address, dec_out_data, golden_bytes[dec_out_address]);
                err_cnt = err_cnt + 1;
            end else begin
                $display("✅ 匹配 [Byte %0d]: 成功纠错并解码出 %h", dec_out_address, dec_out_data);
            end
        end
    end

    // =========================================================================
    // [6] 仿真主流程
    // =========================================================================
    initial begin
        rst_n = 0;
        enc_byte_in = 0;
        enc_byte_vld = 0;
        dec_start = 0;

        // 等待复位释放
        #100;
        rst_n = 1;
        #50;

        $display("=================================================");
        $display("🚀 [1] 启动 RM(1,7) 编码器...");
        
        // 准备 4 个极具代表性的字节作为测试激励
        golden_bytes[0] = 8'hA5; // 1010_0101
        golden_bytes[1] = 8'h3C; // 0011_1100
        golden_bytes[2] = 8'hFF; // 1111_1111
        golden_bytes[3] = 8'h00; // 0000_0000

        // 流水线灌入数据
        enc_byte_in = golden_bytes[0]; enc_byte_vld = 1; #10;
        enc_byte_in = golden_bytes[1]; enc_byte_vld = 1; #10;
        enc_byte_in = golden_bytes[2]; enc_byte_vld = 1; #10;
        enc_byte_in = golden_bytes[3]; enc_byte_vld = 1; #10;
        enc_byte_vld = 0;

        wait(enc_capture_cnt == TEST_BYTES);
        $display("✅ [2] 编码完成，已缓存 4 组 128-bit 码字.");
        $display("⚠️ [3] 故意在码字中翻转 4 个 bit 注入噪声，开始推送给解码器...");
        #50;

        // 启动解码器
        dec_start = 1;
        #10;
        dec_start = 0;

        wait(dec_done == 1);
        $display("=================================================");
        $display("🏁 [4] 解码结束");
        
        if (err_cnt == 0)
            $display("🎉 测试完美通过 (PASS): RM 编解码链路验证成功，且成功纠正了信道噪声！");
        else
            $display("💥 测试失败 (FAIL): 发现 %0d 个字节错误！", err_cnt);

        #100;
        $finish;
    end

endmodule