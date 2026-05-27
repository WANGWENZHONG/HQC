`timescale 1ns / 1ps
module tb_hqc_kem_scheduler;
    reg clk;
    reg rst_n;
    reg start;
    reg [7:0] opcode;
    reg [15:0] host_addr;
    reg [15:0] host_length;
    reg zeroize_req;
    wire ready;
    wire busy;
    wire done;
    wire [7:0] err_status;
    wire [7:0] fault_status;
    wire prim_start;
    wire [7:0] prim_id;
    wire [31:0] prim_arg;
    wire prim_done;
    wire prim_fault;
    wire prim_equal;

    hqc_kem_scheduler dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .start        (start),
        .opcode       (opcode),
        .host_addr    (host_addr),
        .host_length  (host_length),
        .zeroize_req  (zeroize_req),
        .ready        (ready),
        .busy         (busy),
        .done         (done),
        .err_status   (err_status),
        .fault_status (fault_status),
        .prim_start   (prim_start),
        .prim_id      (prim_id),
        .prim_arg     (prim_arg),
        .prim_done    (prim_done),
        .prim_fault   (prim_fault),
        .prim_equal   (prim_equal)
    );

    hqc_primitive_done_model #(
        .LATENCY(2)
    ) model (
        .clk         (clk),
        .rst_n       (rst_n),
        .prim_start  (prim_start),
        .prim_id     (prim_id),
        .prim_arg    (prim_arg),
        .prim_done   (prim_done),
        .prim_fault  (prim_fault),
        .prim_equal  (prim_equal)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task run_opcode;
        input [7:0] op;
        begin
            @(posedge clk);
            opcode <= op;
            start <= 1'b1;
            @(posedge clk);
            start <= 1'b0;
            wait(done == 1'b1);
            @(posedge clk);
        end
    endtask

    initial begin
        rst_n = 1'b0;
        start = 1'b0;
        opcode = 8'd0;
        host_addr = 16'h0100;
        host_length = 16'd0;
        zeroize_req = 1'b0;
        #100;
        rst_n = 1'b1;
        run_opcode(8'h01);
        run_opcode(8'h02);
        run_opcode(8'h03);
        run_opcode(8'h05);
        #200;
        $finish;
    end
endmodule
