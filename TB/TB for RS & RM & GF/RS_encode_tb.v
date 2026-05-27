`timescale 1ns / 1ps

module RS_encode_tb;

    // 参数取 PARAM_HQC = 128 为例
    localparam PARAM_HQC = 128;
    localparam PARAM_N1  = 46;
    localparam PARAM_K   = 16;
    localparam K = 8 * PARAM_K;   // 128 bits
    localparam REG_NUM = 30;

    reg            clk;
    reg            rst_n;
    reg  [K-1:0]   msg_in;
    reg            msg_in_vld;
    reg            msg_in_last;   // 暂不使用

    wire           msg_out_vld;
    wire [7:0]     msg_out;
    wire           done;

    // 时钟生成
    always #5 clk = ~clk;

    // 实例化修正后的编码器
    RS_encode #(
        .PARAM_HQC(PARAM_HQC)
    ) u_dut (
        .clk         (clk),
        .rst_n       (rst_n),
        .msg_in      (msg_in),
        .msg_in_vld  (msg_in_vld),
        .msg_out_vld (msg_out_vld),
        .msg_out     (msg_out),
        .done        (done)
    );

    // 测试激励
    integer i;
    reg [7:0] msg_bytes [0:PARAM_K-1];  // 16 字节

    initial begin
        clk   = 0;
        rst_n = 0;
        msg_in = 0;
        msg_in_vld = 0;

        // 构造简单递增数据
        for (i=0; i<PARAM_K; i=i+1)
            msg_bytes[i] = i + 1;   // 1,2,3,...16

        #20 rst_n = 1;
        #10;

        // 逐个发送字节
        for (i=0; i<PARAM_K; i=i+1) begin
            @(posedge clk);
            msg_in <= {msg_in[K-9:0], msg_bytes[i]}; // 拼成 128bit，从高字节发送？
            // 简单处理：只取最低字节填充，完整帧需要根据协议。这里简化，每次送入一个字节到 msg_in 的最低字节。
            // 实际原代码 msg_in 是 K 位宽，应一次送一整帧。为了符合设计，可改为一次送满 K 位。
        end
		msg_in_vld <= 1;
        // 等待 done
        @(posedge clk);
        msg_in_vld <= 0;

        wait(done == 1);
        #20 $finish;
    end

    // 监视输出
    always @(posedge clk) begin
        if (msg_out_vld)
            $display("Time %t : msg_out = %h", $time, msg_out);
        if (done)
            $display("Time %t : Encoding done.", $time);
    end

endmodule
