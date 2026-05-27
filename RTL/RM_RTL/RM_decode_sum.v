// ============================================================
//  RM_decode_sum.v  —  多次RM码的求和模块
//
//  输入：直接由外部ram读出，每次连续读MULTIPLICITY个128bit数据
//        
//  输出：流水化输出求和后的数据，输出完成一组数据后，进行下一组数据的处理和输出，实现全流水
// ============================================================
module RM_decode_sum #(
    parameter PARAM_HQC = 128,
    parameter MULTIPLICITY   = (PARAM_HQC == 128)? 3 : 5,
	parameter DATAWIDTH		 = (PARAM_HQC == 128)? 2 : 3
)(
    input                   clk,
    input                   rst_n,
    input                   data_in_en,
    input   [127:0]         data_in,
    input                   data_in_vld,
    output                  sum_ready,
    output  [DATAWIDTH-1:0] data_sum_0,
    output  [DATAWIDTH-1:0] data_sum_1,
    output                  data_sum_vld,
    output                  data_out_start
);

    // 状态机定义
    localparam S_IDLE     = 2'd0;
    localparam S_COLLECT  = 2'd1;
    localparam S_SUM      = 2'd2;

    // 已声明信号
    reg         [2:0]          cnt_mult_in; 
    reg         [127:0]        data_ca [0:MULTIPLICITY-1];

    // 补充内部信号
    reg         [1:0]          state, next_state;
    reg         [5:0]          addr;             // 输出对地址 0 ~ 63

//==================== 状态机时序 ====================
    always @(posedge clk) begin
        if (!rst_n) begin
            state      <= S_IDLE;
            cnt_mult_in <= 0;
            addr       <= 0;
        end else begin
            case (state)
                S_IDLE: begin
                    if (data_in_en) begin
                        state      <= S_COLLECT;
                        cnt_mult_in <= 0;
                        addr       <= 0;
                    end
                end
                S_COLLECT: begin
                    if (data_in_vld) begin
                        data_ca[cnt_mult_in] <= data_in;
                        if (cnt_mult_in == MULTIPLICITY - 1) begin
                            state <= S_SUM;
                            addr  <= 0;
							
                        end else begin
                            cnt_mult_in <= cnt_mult_in + 1;
                        end
                    end
                end
                S_SUM: begin
                    if (addr == 63) begin
                        state <= S_IDLE;
						cnt_mult_in <= 3'b0;
                    end else begin
                        addr <= addr + 1;
                    end
                end
                default: state <= S_IDLE;
            endcase
        end
    end
//==================== 求和组合逻辑 ====================
	generate
	if(MULTIPLICITY==3)begin
	assign data_sum_0 = data_ca[0][addr*2] + data_ca[1][addr*2] + data_ca[2][addr*2];
	assign data_sum_1 = data_ca[0][addr*2+1] + data_ca[1][addr*2+1] + data_ca[2][addr*2+1];
	end
	else if(MULTIPLICITY==5)begin
	assign data_sum_0 = data_ca[0][addr*2] + data_ca[1][addr*2] + data_ca[2][addr*2] + data_ca[3][addr*2] + data_ca[4][addr*2];
	assign data_sum_1 = data_ca[0][addr*2+1] + data_ca[1][addr*2+1] + data_ca[2][addr*2+1] + data_ca[3][addr*2]++ data_ca[4][addr*2];
	end
	endgenerate
//==================== 模块输出 ====================
    assign sum_ready      = (state != S_SUM) && (cnt_mult_in != MULTIPLICITY - 1);
    assign data_sum_vld   = (state == S_SUM);
    assign data_out_start = (state == S_SUM) && (addr == 0);

endmodule