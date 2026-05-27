`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/05/04 14:59:56
// Design Name: 
// Module Name: ha_layer_tb
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


// ============================================================
//  tb_ha_layer.v  —  ha_layer 全流水测试台
//
//  测试场景：
//    - 连续输入3批数据（每批64对），无间隙
//    - 验证全流水处理：第1批读出时第2批已在写入
//    - 检查输出数据正确性（蝶形运算：sum=a+b, diff=a-b）
// ============================================================
`timescale 1ns/1ps

module tb_ha_layer;

// ------------------------------------------------------------------
//  参数配置
// ------------------------------------------------------------------
parameter DATA_IN_W  = 4;
parameter DATA_OUT_W = 5;
parameter STAGE_IDX  = 0;
parameter CLK_PERIOD = 10;

// ------------------------------------------------------------------
//  信号声明
// ------------------------------------------------------------------
reg                       clk;
reg                       rst;
reg                       din_valid;
reg                       din_start;
reg  [DATA_IN_W-1:0]      din_a;
reg  [DATA_IN_W-1:0]      din_b;
wire                      dout_valid;
wire                      dout_start;
wire [DATA_OUT_W-1:0]     dout_a;
wire [DATA_OUT_W-1:0]     dout_b;

// ------------------------------------------------------------------
//  DUT 实例化
// ------------------------------------------------------------------
ha_layer #(
    .DATA_IN_W (DATA_IN_W),
    .DATA_OUT_W(DATA_OUT_W),
    .STAGE_IDX (STAGE_IDX)
) u_dut (
    .clk        (clk),
    .rst        (rst),
    .din_valid  (din_valid),
    .din_start  (din_start),
    .din_a      (din_a),
    .din_b      (din_b),
    .dout_valid (dout_valid),
    .dout_start (dout_start),
    .dout_a     (dout_a),
    .dout_b     (dout_b)
);

// ------------------------------------------------------------------
//  时钟生成
// ------------------------------------------------------------------
initial begin
    clk = 0;
    forever #(CLK_PERIOD/2) clk = ~clk;
end

// ------------------------------------------------------------------
//  输入数据生成：连续3批，每批64对
// ------------------------------------------------------------------
integer batch;
integer pair_idx;
reg signed [DATA_IN_W-1:0] data_a_vec [0:191];  // 3批×64对
reg signed [DATA_IN_W-1:0] data_b_vec [0:191];

initial begin
    // 生成测试数据：简单规律便于验证
    for (batch = 0; batch < 3; batch = batch + 1) begin
        for (pair_idx = 0; pair_idx < 64; pair_idx = pair_idx + 1) begin
            data_a_vec[batch*64 + pair_idx] = (batch*64 + pair_idx) % 16 - 8;  // -8~7循环
            data_b_vec[batch*64 + pair_idx] = (pair_idx % 8) - 4;              // -4~3循环
        end
    end
end

// ------------------------------------------------------------------
//  激励生成
// ------------------------------------------------------------------
initial begin
    rst       = 1;
    din_valid = 0;
    din_start = 0;
    din_a     = 0;
    din_b     = 0;

    #(CLK_PERIOD*5);
    rst = 0;
    #(CLK_PERIOD*2);

    // 连续输入3批数据，每批64对，无间隙
    for (batch = 0; batch < 3; batch = batch + 1) begin
        for (pair_idx = 0; pair_idx < 64; pair_idx = pair_idx + 1) begin
            @(posedge clk);
            din_valid = 1;
            din_start = pair_idx == 0 ? 1 : 0;  // 只在第一批第一对拉高
            din_a     = data_a_vec[batch*64 + pair_idx];
            din_b     = data_b_vec[batch*64 + pair_idx];
        end
    end

    @(posedge clk);
    din_valid = 0;
    din_start = 0;

    // 等待所有输出完成
    #(CLK_PERIOD*200);
    $display("========================================");
    $display("Testbench finished");
    $display("========================================");
    $finish;
end

// ------------------------------------------------------------------
//  输出监测与自检
// ------------------------------------------------------------------
integer out_pair_cnt;
integer out_batch_cnt;
integer out_phase;  // 0=sum, 1=diff
reg signed [DATA_OUT_W-1:0] expected_a, expected_b;
reg signed [DATA_IN_W-1:0]  orig_a, orig_b;
integer global_out_idx;

initial begin
    out_pair_cnt   = 0;
    out_batch_cnt  = 0;
    out_phase      = 0;  // 先输出sum
    global_out_idx = 0;
end

always @(posedge clk) begin
    if (rst) begin
        out_pair_cnt   <= 0;
        out_batch_cnt  <= 0;
        out_phase      <= 0;
        global_out_idx <= 0;
    end else if (dout_valid) begin
        // 计算期望值
        if (out_phase == 0) begin
            // sum阶段：输出的是偶数对和奇数对的和数据配对
            // dout_a来自even_sum，对应输入第 2*out_pair_cnt 对
            // dout_b来自odd_sum，对应输入第 2*out_pair_cnt+1 对
            orig_a = data_a_vec[out_batch_cnt*64 + 2*out_pair_cnt];
            orig_b = data_b_vec[out_batch_cnt*64 + 2*out_pair_cnt];
            expected_a = $signed({orig_a[DATA_IN_W-1], orig_a}) + 
                         $signed({orig_b[DATA_IN_W-1], orig_b});
            
            orig_a = data_a_vec[out_batch_cnt*64 + 2*out_pair_cnt + 1];
            orig_b = data_b_vec[out_batch_cnt*64 + 2*out_pair_cnt + 1];
            expected_b = $signed({orig_a[DATA_IN_W-1], orig_a}) + 
                         $signed({orig_b[DATA_IN_W-1], orig_b});
        end else begin
            // diff阶段
            orig_a = data_a_vec[out_batch_cnt*64 + 2*out_pair_cnt];
            orig_b = data_b_vec[out_batch_cnt*64 + 2*out_pair_cnt];
            expected_a = $signed({orig_a[DATA_IN_W-1], orig_a}) - 
                         $signed({orig_b[DATA_IN_W-1], orig_b});
            
            orig_a = data_a_vec[out_batch_cnt*64 + 2*out_pair_cnt + 1];
            orig_b = data_b_vec[out_batch_cnt*64 + 2*out_pair_cnt + 1];
            expected_b = $signed({orig_a[DATA_IN_W-1], orig_a}) - 
                         $signed({orig_b[DATA_IN_W-1], orig_b});
        end

        // 检查输出
        if (dout_a !== expected_a || dout_b !== expected_b) begin
            $display("[ERROR] @%0t: Batch=%0d, Phase=%s, Pair=%0d", 
                     $time, out_batch_cnt, (out_phase==0)?"SUM":"DIFF", out_pair_cnt);
            $display("        dout_a=%0d (exp=%0d), dout_b=%0d (exp=%0d)",
                     $signed(dout_a), expected_a, $signed(dout_b), expected_b);
        end else begin
            $display("[PASS]  @%0t: Batch=%0d, Phase=%s, Pair=%0d, dout_a=%0d, dout_b=%0d",
                     $time, out_batch_cnt, (out_phase==0)?"SUM":"DIFF", 
                     out_pair_cnt, $signed(dout_a), $signed(dout_b));
        end

        // 计数更新
        if (out_pair_cnt == 31) begin
            out_pair_cnt = 0;
            if (out_phase == 0) begin
                out_phase = 1;  // sum→diff
            end else begin
                out_phase = 0;  // diff→sum，进入下一批
                out_batch_cnt = out_batch_cnt + 1;
            end
        end else begin
            out_pair_cnt = out_pair_cnt + 1;
        end

        global_out_idx = global_out_idx + 1;
    end

    // 监测start信号
    if (dout_start) begin
        $display("========================================");
        $display("[INFO]  @%0t: dout_start asserted", $time);
        $display("========================================");
    end
end

// ------------------------------------------------------------------
//  波形dump
// ------------------------------------------------------------------
initial begin
    $dumpfile("ha_layer.vcd");
    $dumpvars(0, tb_ha_layer);
end

// ------------------------------------------------------------------
//  超时保护
// ------------------------------------------------------------------
initial begin
    #(CLK_PERIOD*500);
    $display("[TIMEOUT] Simulation timeout!");
    $finish;
end

endmodule
