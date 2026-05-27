// ============================================================
// RM译码顶层模块·
//
//
// ============================================================
module RM_decode_top #(
    parameter PARAM_HQC = 128, 
    parameter MULTIPLICITY   = (PARAM_HQC == 128)? 3 : 5,
    // 求和模块输出数据的位宽
    parameter SUM_O_W        = (PARAM_HQC == 128)? 2 : 3,
    // 输入数据地址位宽（取决于需要存入的 128-bit 数据块个数）
    parameter DATA_IN_W      = (PARAM_HQC == 128)? 8 :
                               (PARAM_HQC == 192)? 9 :
                               (PARAM_HQC == 256)? 9 : 8,
    // 需要译码的 RM 码元个数（输出字节数）
    parameter BYTE_NUM       = (PARAM_HQC == 128)? 46 :
                               (PARAM_HQC == 192)? 56 :
                               (PARAM_HQC == 256)? 90 : 46,
    // 输出数据地址位宽
    parameter DATA_OUT_W     = (PARAM_HQC == 128)? 6 :
                               (PARAM_HQC == 192)? 6 :
                               (PARAM_HQC == 256)? 7 : 6,
    // FHT（快速哈达玛变换）后求和数据的位宽
    parameter After_FHT_W    = (PARAM_HQC == 128)? 10 : 11
)(
    input                        clk,               
    input                        rst_n,            
    input                        decode_start,      // 译码开始脉冲（高有效）
    input        [127:0]         data_in,           // 输入数据（128 bit 一组）
    input                        data_in_vld,       // 输入数据有效标志
    output                       data_in_ready,     // 准备好接收下一组输入数据（一次有效MULTIPLICITY拍）
    output  reg  [DATA_IN_W-1:0] data_in_address,   // 输入数据地址（通过地址读取外部数据）
    output                       data_out_vld,      // 输出数据有效标志
    output        [7:0]          data_out,          // 译码输出字节
    output  reg  [DATA_OUT_W-1:0]data_out_address,  // 输出数据地址
    output                       decode_done        // 译码完成标志
);
    // =========================================================================
    // 内部寄存器与连线
    // =========================================================================
    reg     [2:0]               cnt_mult_in;     // 重复次数计数器（计数到 MULTIPLICITY-1）
    reg     [DATA_IN_W-1 :0]    cnt_data_in;     // 已输入的数据组总数计数器
    reg                         decode_en;       // 译码使能信号（贯穿整个译码过程）

    wire                        sum_ready;       // 求和模块准备好接收新数据
    wire                        findpeak_vld;    // 峰值检测输出有效
    
    // 求和模块输出
    wire    [SUM_O_W-1 : 0]     data_sum_0;
    wire    [SUM_O_W-1 : 0]     data_sum_1;
    wire                        data_sum_vld;
    wire                        data_out_start;  // 求和模块输出的数据块起始脉冲（连到 HA 模块的输入启动）
    // FHT 模块输出
    wire    [After_FHT_W-1 : 0] data_HA_0;
    wire    [After_FHT_W-1 : 0] data_HA_1;
    wire                        data_HA_vld;
    wire                        data_HA_start;   // HA 模块输出数据块的起始脉冲

    // =========================================================================
    // 译码使能信号 decode_en
    // 在 decode_start 脉冲时置位，在 decode_done 时清除
    // =========================================================================
    always @(posedge clk) begin
        if (!rst_n)                           
            decode_en <= 1'b0;
        else if (decode_start)
            decode_en <= 1'b1;
        else if (decode_done)
            decode_en <= 1'b0;
    end

    // =========================================================================
    // 输入数据总数计数器 cnt_data_in
    // 记录自译码开始以来已接收的数据组数，在 data_in_vld 时递增
    // 在 decode_start 或 decode_done 时清零
    // =========================================================================
    always @(posedge clk) begin
        if (!rst_n)
            cnt_data_in <= 'd0;
        else if (data_in_vld)
            cnt_data_in <= cnt_data_in + 1'b1;
        else if (decode_done | decode_start)
            cnt_data_in <= 'd0;
    end

    // =========================================================================
    // data_in_ready：向上游模块指示可以接收下一组数据
    // 条件：求和模块准备好、译码使能有效、且尚未接收完全部所需数据
    // 总需接收 BYTE_NUM * MULTIPLICITY 组数据，最后一组索引为 BYTE_NUM*MULTIPLICITY-1
    // 当 cnt_data_in == BYTE_NUM*MULTIPLICITY-1 时，ready 拉低（等待最后一个有效数据）
    // =========================================================================
    assign data_in_ready = sum_ready && decode_en && (cnt_data_in != BYTE_NUM*MULTIPLICITY-1);

    // =========================================================================
    // 输入数据地址生成
    // 每次 data_in_ready 有效时地址递增，指向下一存储位置
    // 在 decode_start 或 decode_done 时归零
    // =========================================================================
    always @(posedge clk) begin
        if (!rst_n)
            data_in_address <= 'd0;
        else if (data_in_ready)
            data_in_address <= data_in_address + 1'b1;
        else if (decode_done | decode_start)
            data_in_address <= 'd0;
    end

    // =========================================================================
    // 输出数据地址生成
    // 每检测到一个有效峰值（findpeak_vld），输出地址递增
    // 在译码完成时归零
    // =========================================================================
    always @(posedge clk) begin
        if (!rst_n)
            data_out_address <= 'd0;
        else if (findpeak_vld)
            data_out_address <= data_out_address + 1'b1;
        else if (decode_done)
            data_out_address <= 'd0;
    end

    // =========================================================================
    // 译码完成标志 decode_done
    // 当输出最后一个字节（地址达到 BYTE_NUM-1）且该字节有效时产生脉冲
    // =========================================================================
    assign decode_done = (data_out_address == BYTE_NUM-1) ? findpeak_vld : 1'b0;

    // 输出数据有效信号直接来自峰值检测模块的有效输出
    assign data_out_vld = findpeak_vld;

    // -------------------- 求和模块 RM_decode_sum ---------------------------
    // 功能：将多次重复输入的 128-bit 数据进行按位累加（重复码合并），
    //       输出两路求和结果 data_sum_0/data_sum_1，以及数据块起始脉冲 data_out_start
    // -----------------------------------------------------------------------
    RM_decode_sum #(
        .PARAM_HQC   (PARAM_HQC)
    ) RM_decode_sum_inst (
        .clk            (clk),
        .rst_n          (rst_n),
        .data_in_en     (data_in_ready),   // 输入使能，接到顶层 ready 信号
        .data_in        (data_in),
        .data_in_vld    (data_in_vld),
        .sum_ready      (sum_ready),       // 求和模块准备好信号，反馈给顶层
        .data_sum_0     (data_sum_0),
        .data_sum_1     (data_sum_1),
        .data_sum_vld   (data_sum_vld),
        .data_out_start (data_out_start)   // 每完成一组字节的求和后给出启动脉冲
    );

    // -------------------- 哈达玛变换顶层模块 RM_HA_top ---------------------
    // 功能：对求和结果进行快速哈达玛变换（FHT），得到两路变换值 data_HA_0/data_HA_1，
    //       并产生数据有效标志 data_HA_vld 和起始脉冲 data_HA_start
    // -----------------------------------------------------------------------
    RM_HA_top #(
        .PARAM_HQC   (PARAM_HQC)
    ) RM_HA_top_inst (
        .clk            (clk),
        .rst_n          (rst_n),
        .data_in_start  (data_out_start),  // 由求和模块给出的启动脉冲
        .data_sum_0     (data_sum_0),
        .data_sum_1     (data_sum_1),
        .data_sum_vld   (data_sum_vld),
        .data_HA_vld    (data_HA_vld),
        .data_HA_0      (data_HA_0),
        .data_HA_1      (data_HA_1),
        .data_HA_start  (data_HA_start)
    );

    // -------------------- 峰值检测模块 peak_detect -------------------------
    // 功能：比较 FHT 输出的两路数据，找出峰值位置，译码得到最终 8-bit 输出 data_out，
    //       同时输出有效标志 findpeak_vld
    // -----------------------------------------------------------------------
    peak_detect #(
        .PARAM_HQC   (PARAM_HQC)
    ) peak_detect_inst (
        .clk            (clk),
        .rst_n          (rst_n),
        .data_in_start  (data_HA_start),
        .din_a          (data_HA_0),
        .din_b          (data_HA_1),
        .din_valid      (data_HA_vld),
        .dout           (data_out),
        .dout_valid     (findpeak_vld)
    );

endmodule