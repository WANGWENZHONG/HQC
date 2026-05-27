// ============================================================
//  ha_layer.v  —  单级哈达玛蝶形流水
//
//  4个FIFO，深度64，支持同读同写：
//    FIFO_even_sum  : 偶数对的和
//    FIFO_odd_sum   : 奇数对的和
//    FIFO_even_diff : 偶数对的差
//    FIFO_odd_diff  : 奇数对的差
//
//  写入规则：
//    输入第k对(din_a, din_b)，k=0..63
//    sum = din_a + din_b, diff = din_a - din_b
//    k为偶数 → 写 FIFO_even_sum, FIFO_even_diff
//    k为奇数 → 写 FIFO_odd_sum,  FIFO_odd_diff
//
//  读出规则：
//    输入满32对后触发读出
//    阶段1：读 FIFO_even_sum + FIFO_odd_sum，32拍，配对输出
//    阶段2：读 FIFO_even_diff + FIFO_odd_diff，32拍，配对输出
//
//  同读同写：下一批写入时上一批diff可能未读完，
//            
// ============================================================
module ha_layer #(
    parameter DATA_IN_W  = 2,
    parameter DATA_OUT_W = 3,
    parameter STAGE_IDX  = 0
)(
    input                       clk,
    input                       rst_n,
    input                       din_valid,
    input                       din_start,
    input  [DATA_IN_W-1:0]      din_a,
    input  [DATA_IN_W-1:0]      din_b,
    output reg                  dout_valid,
    output reg                  dout_start,
    output reg [DATA_OUT_W-1:0] dout_a,
    output reg [DATA_OUT_W-1:0] dout_b
);
//==================== Layer 0 ====================

// ------------------------------------------------------------------
//  蝶形计算（组合逻辑）
// ------------------------------------------------------------------
wire [DATA_OUT_W-1:0] butterfly_sum  =
    $signed({din_a[DATA_IN_W-1], din_a}) +
    $signed({din_b[DATA_IN_W-1], din_b});

wire [DATA_OUT_W-1:0] butterfly_diff =
    $signed({din_a[DATA_IN_W-1], din_a}) -
    $signed({din_b[DATA_IN_W-1], din_b});

// ------------------------------------------------------------------
//  写侧控制
// ------------------------------------------------------------------
reg [5:0] wr_pair_cnt;   // 0..63，当前对计数
wire      wr_is_odd = wr_pair_cnt[0];

always @(posedge clk) begin
    if (!rst_n)
        wr_pair_cnt <= 6'd0;
    else if (din_valid)
        wr_pair_cnt <= (wr_pair_cnt == 6'd63) ? 6'd0 : wr_pair_cnt + 1'b1;
end

// 4个FIFO的写使能
wire wr_en_even_sum  = din_valid && !wr_is_odd;
wire wr_en_odd_sum   = din_valid &&  wr_is_odd;
wire wr_en_even_diff = din_valid && !wr_is_odd;
wire wr_en_odd_diff  = din_valid &&  wr_is_odd;

// ------------------------------------------------------------------
//  读侧状态机
//  触发：wr_pair_cnt == 32 且 din_valid（输入满33对）
//  RD_IDLE  → RD_SUM(33拍) → RD_DIFF(33拍) → RD_IDLE
// ------------------------------------------------------------------
localparam RD_IDLE = 2'd0,
           RD_SUM  = 2'd1,
           RD_DIFF = 2'd2;

reg [1:0] rd_state;
reg [4:0] rd_cnt;      // 0..31

// 触发信号：写入第33对时（wr_pair_cnt为32的那拍）
wire rd_trigger = din_valid && (wr_pair_cnt == 6'd32);

reg rd_en_sum;
reg rd_en_diff;

always @(posedge clk) begin
    if (!rst_n) begin
        rd_state   <= RD_IDLE;
        rd_cnt     <= 5'd0;
        rd_en_sum  <= 1'b0;
        rd_en_diff <= 1'b0;
    end else begin
        case (rd_state)
            RD_IDLE: begin
                rd_en_sum  <= 1'b0;
                rd_en_diff <= 1'b0;
                if (rd_trigger) begin
                    rd_state  <= RD_SUM;
                    rd_cnt    <= 5'd0;
                    rd_en_sum <= 1'b1;
                end
            end

            RD_SUM: begin
                if (rd_cnt == 5'd31) begin
                    rd_cnt     <= 5'd0;
                    rd_state   <= RD_DIFF;
                    rd_en_sum  <= 1'b0;
                    rd_en_diff <= 1'b1;
                end else begin
                    rd_cnt <= rd_cnt + 1'b1;
                end
            end

            RD_DIFF: begin
                if (rd_cnt == 5'd31) begin
                    rd_cnt     <= 5'd0;
                    rd_en_diff <= 1'b0;
                    // 若此时恰好又有新触发，直接跳转RD_SUM
                    if (rd_trigger) begin
                        rd_state  <= RD_SUM;
                        rd_en_sum <= 1'b1;
                    end else begin
                        rd_state  <= RD_IDLE;
                    end
                end else begin
                    rd_cnt <= rd_cnt + 1'b1;
                end
            end

            default: rd_state <= RD_IDLE;
        endcase
    end
end

// ------------------------------------------------------------------
//  4个FIFO实例（深度32，支持同读同写）
// ------------------------------------------------------------------
wire [DATA_OUT_W-1:0] dout_even_sum, dout_odd_sum;
wire [DATA_OUT_W-1:0] dout_even_diff, dout_odd_diff;

sync_fifo_rw #(.DATA_W(DATA_OUT_W), .DEPTH(32)) u_even_sum (
    .clk   (clk),
    .rst_n (rst_n),
    .wr_en (wr_en_even_sum),
    .din   (butterfly_sum),
    .rd_en (rd_en_sum),
    .dout  (dout_even_sum),
    .full  (),
    .empty ()
);

sync_fifo_rw #(.DATA_W(DATA_OUT_W), .DEPTH(32)) u_odd_sum (
    .clk   (clk),
    .rst_n (rst_n),
    .wr_en (wr_en_odd_sum),
    .din   (butterfly_sum),
    .rd_en (rd_en_sum),
    .dout  (dout_odd_sum),
    .full  (),
    .empty ()
);

sync_fifo_rw #(.DATA_W(DATA_OUT_W), .DEPTH(32)) u_even_diff (
    .clk   (clk),
    .rst_n (rst_n),
    .wr_en (wr_en_even_diff),
    .din   (butterfly_diff),
    .rd_en (rd_en_diff),
    .dout  (dout_even_diff),
    .full  (),
    .empty ()
);

sync_fifo_rw #(.DATA_W(DATA_OUT_W), .DEPTH(32)) u_odd_diff (
    .clk   (clk),
    .rst_n (rst_n),
    .wr_en (wr_en_odd_diff),
    .din   (butterfly_diff),
    .rd_en (rd_en_diff),
    .dout  (dout_odd_diff),
    .full  (),
    .empty ()
);

// ------------------------------------------------------------------
//  输出寄存（FIFO组合读出，打一拍对齐）
//  dout_a = even侧，dout_b = odd侧
// ------------------------------------------------------------------
reg start_pending;

always @(posedge clk) begin
    if (!rst_n) begin
        start_pending <= 1'b0;
        dout_valid    <= 1'b0;
        dout_start    <= 1'b0;
        dout_a        <= {DATA_OUT_W{1'b0}};
        dout_b        <= {DATA_OUT_W{1'b0}};
    end else begin
        if (din_start)
            start_pending <= 1'b1;

        if (rd_en_sum || rd_en_diff) begin
            dout_valid <= 1'b1;
            dout_a     <= rd_en_sum ? dout_even_sum  : dout_even_diff;
            dout_b     <= rd_en_sum ? dout_odd_sum   : dout_odd_diff;

            // 第一拍有效输出时拉高dout_start
            if (start_pending && rd_en_sum) begin
                dout_start    <= 1'b1;
                start_pending <= 1'b0;
            end else begin
                dout_start <= 1'b0;
            end
        end else begin
            dout_valid <= 1'b0;
            dout_start <= 1'b0;
        end
    end
end

endmodule


module sync_fifo_rw #(
    parameter DATA_W = 4,
    parameter DEPTH  = 64
)(
    input               clk,
    input               rst_n,
    input               wr_en,
    input  [DATA_W-1:0] din,
    input               rd_en,
    output [DATA_W-1:0] dout,
    output              full,
    output              empty
);
    localparam PTR_W = $clog2(DEPTH);  // 6bit（深度64）

    // ------------------------------------------------------------------
    //  存储体
    // ------------------------------------------------------------------
    reg [DATA_W-1:0] mem [0:DEPTH-1];

    // ------------------------------------------------------------------
    //  地址寄存器：当前地址 + 预计算下一地址
    //  避免实时加法出现在满/空判断的组合路径上
    // ------------------------------------------------------------------
    reg [PTR_W-1:0] wr_addr,      rd_addr;
    reg [PTR_W-1:0] next_wr_addr, next_rd_addr;

    // ------------------------------------------------------------------
    //  满/空：1bit寄存器直接输出，不用计数器比较
    // ------------------------------------------------------------------
    reg full_r, empty_r;
    assign full  = full_r;
    assign empty = empty_r;

    // ------------------------------------------------------------------
    //  有效读写：同第二个模块的处理方式
    //  满时若同时有读则允许写（不丢数据）
    //  空时若同时有写则允许读（透传）
    // ------------------------------------------------------------------
    wire wr_v = wr_en && (!full_r  || rd_en);
    wire rd_v = rd_en && (!empty_r || wr_en);

    // ------------------------------------------------------------------
    //  组合读出（保留0拍延迟，满足ha_layer需求）
    //  空时同时读写：直接透传din，不读旧数据
    // ------------------------------------------------------------------
    assign dout = (empty_r && wr_en) ? din : mem[rd_addr];

    // ------------------------------------------------------------------
    //  写操作
    // ------------------------------------------------------------------
    always @(posedge clk) begin
        if (wr_v)
            mem[wr_addr] <= din;
    end

    // ------------------------------------------------------------------
    //  写地址更新（使用预计算值）
    // ------------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            wr_addr      <= {PTR_W{1'b0}};
            next_wr_addr <= {{(PTR_W-1){1'b0}}, 1'b1};  // 初始为1
        end else if (wr_v) begin
            wr_addr      <= next_wr_addr;
            next_wr_addr <= next_wr_addr + 1'b1;
        end
    end

    // ------------------------------------------------------------------
    //  读地址更新（使用预计算值）
    // ------------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            rd_addr      <= {PTR_W{1'b0}};
            next_rd_addr <= {{(PTR_W-1){1'b0}}, 1'b1};  // 初始为1
        end else if (rd_v) begin
            rd_addr      <= next_rd_addr;
            next_rd_addr <= next_rd_addr + 1'b1;
        end
    end

    // ------------------------------------------------------------------
    //  满标志更新
    //  写后下一写地址追上读地址 → 满
    //  有读操作 → 不可能继续满
    // ------------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n)
            full_r <= 1'b0;
        else if (rd_en)
            full_r <= full_r && wr_en;      // 有读：满状态只在同时写时保持
        else if (wr_v)
            full_r <= (next_wr_addr == rd_addr);  // 写后下一地址追上读地址
    end

    // ------------------------------------------------------------------
    //  空标志更新
    //  读后下一读地址追上写地址 → 空
    //  有写操作 → 不可能继续空
    // ------------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n)
            empty_r <= 1'b1;
        else if (wr_en)
            empty_r <= rd_en ? empty_r : 1'b0;   // 有写：空状态只在同时读时保持
        else if (rd_v)
            empty_r <= (next_rd_addr == wr_addr); // 读后下一地址追上写地址
    end

endmodule