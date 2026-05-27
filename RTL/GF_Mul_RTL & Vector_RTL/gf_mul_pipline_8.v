`timescale 1ns / 1ps
module gf_mul_pipline_8 (
    input         							clk,
	input									rst_n,
    input         							start,
    input				[7:0]  				in_1,
    input  				[7:0]  				in_2,
    output 		reg		[7:0]  				out,
    output      reg  						done
);

// ------------------------------------------------------------------
//  Stage 
// ------------------------------------------------------------------
reg [7:0] step_1_reg;
reg [7:0] step_2_reg;
reg [7:0] step_3_reg;
reg [7:0] step_4_reg;
reg [7:0] step_5_reg;
reg [7:0] step_6_reg;
reg [7:0] step_7_reg;
reg [7:0] store_1;
reg [7:0] store_2;
reg [7:0] store_3;
reg [7:0] store_4;
reg [7:0] store_5;
reg [7:0] store_6;
reg [7:0] store_7;

reg ca_vld_1;
reg ca_vld_2;
reg ca_vld_3;
reg ca_vld_4;
reg ca_vld_5;
reg ca_vld_6;
reg ca_vld_7;


always @(posedge clk)begin
	if (!rst_n)begin
		step_1_reg <= 8'd0;
		ca_vld_1   <= 1'd0;
	end
	else begin	
		step_1_reg <= in_2[7] ? in_1 : 8'h00;
		ca_vld_1   <= start;
	end
end

always @(posedge clk)begin
	store_1 <= in_2;
	store_0_1 <= in_1;
end	

always @(posedge clk)begin
	if (!rst_n)begin
		step_2_reg <= 8'd0;
		ca_vld_2   <= 1'd0;
	end
	else begin
		step_2_reg <= (step_1_reg[7] ? ({step_1_reg[6:0], 1'b0} ^ 8'h1D) : {step_1_reg[6:0], 1'b0}) ^ (store_1[6] ? store_0_1 : 8'h00);
		ca_vld_2   <= ca_vld_1;
	end
end

always @(posedge clk)begin
	store_2 <= store_1;
	store_0_2 <= store_0_1;
end	

always @(posedge clk)begin
	if (!rst_n)begin
		step_3_reg <= 8'd0;
		ca_vld_3   <= 1'd0;
	end
	else begin
		step_3_reg <= (step_2_reg[7] ? ({step_2_reg[6:0], 1'b0} ^ 8'h1D) : {step_2_reg[6:0], 1'b0}) ^ (store_2[5] ? store_0_2 : 8'h00);
		ca_vld_3   <= ca_vld_2;
	end
end

always @(posedge clk)begin
	store_3 <= store_2;
	store_0_3 <= store_0_2;
end	

always @(posedge clk)begin
	if (!rst_n)begin
		step_4_reg <= 8'd0;
		ca_vld_4   <= 1'd0;
	end
	else begin
		step_4_reg <= (step_3_reg[7] ? ({step_3_reg[6:0], 1'b0} ^ 8'h1D) : {step_3_reg[6:0], 1'b0}) ^ (store_3[4] ? store_0_3 : 8'h00);
		ca_vld_4   <= ca_vld_3;
	end
end

always @(posedge clk)begin
	store_4 <= store_3;
	store_0_4 <= store_0_3;
end

always @(posedge clk)begin
	if (!rst_n)begin
		step_5_reg <= 8'd0;
		ca_vld_5   <= 1'd0;
	end
	else begin
		step_5_reg <= (step_4_reg[7] ? ({step_4_reg[6:0], 1'b0} ^ 8'h1D) : {step_4_reg[6:0], 1'b0}) ^ (store_4[3] ? store_0_4 : 8'h00);
		ca_vld_5   <= ca_vld_4;
	end
end
 
always @(posedge clk)begin
	store_5 <= store_4;
	store_0_5 <= store_0_4;
end
 
always @(posedge clk)begin
	if (!rst_n)begin
		step_6_reg <= 8'd0;
		ca_vld_6   <= 1'd0;
	end
	else begin
		step_6_reg <= (step_5_reg[7] ? ({step_5_reg[6:0], 1'b0} ^ 8'h1D) : {step_5_reg[6:0], 1'b0}) ^ (store_5[2] ? store_0_5 : 8'h00);
		ca_vld_6   <= ca_vld_5;
	end
end

always @(posedge clk)begin
	store_6 <= store_5;
	store_0_6 <= store_0_5;
end

always @(posedge clk)begin
	if (!rst_n)begin
		step_7_reg <= 8'd0;
		ca_vld_7   <= 1'd0;
	end
	else begin
		step_7_reg <= (step_6_reg[7] ? ({step_6_reg[6:0], 1'b0} ^ 8'h1D) : {step_6_reg[6:0], 1'b0}) ^ (store_6[1] ? store_0_6 : 8'h00);
		ca_vld_7   <= ca_vld_6;
	end
end

always @(posedge clk)begin
	store_7 <= store_6;
	store_0_7 <= store_0_6;
end

always @(posedge clk)begin
	if (!rst_n)begin
		out <= 8'd0;
		done   <= 1'd0;
	end
	else begin
		out <= (step_7_reg[7] ? ({step_7_reg[6:0], 1'b0} ^ 8'h1D) : {step_7_reg[6:0], 1'b0}) ^ (store_7[0] ? store_0_7 : 8'h00);
		done   <= ca_vld_7;
	end
end  

endmodule
