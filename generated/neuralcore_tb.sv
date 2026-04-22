`timescale 1ns/1ps

module neuralcore_tb;

    logic clk = 0;
    logic rst_n = 0;

    logic [7:0] cpu_control = 0;
    logic [7:0] cpu_status;
    logic [3:0] cpu_opcode = 0;
    logic signed [15:0] cpu_write_data = 0;
    logic [17:0] cpu_write_addr = 0;
    logic cpu_write_en = 0;
    logic cpu_read_en = 0;

    neuralcore uut (
        .clk(clk),
        .rst_n(rst_n)
    );

    always #5 clk = ~clk;

    integer cycle;
    initial begin
        cycle = 0;

        $dumpfile("waveform.vcd");
        $dumpvars(0, uut);

        rst_n = 0;
        clk = 0;

        #100;
        rst_n = 1;
        #100;

        $display("=== Test 1: Sync control (control=1) ===");
        cpu_control = 1;
        #100;
        cpu_control = 0;
        #100;

        $display("=== Test 2: Load weight data ===");
        cpu_control = 1;
        cpu_write_addr = 0;
        cpu_write_data = 16'h0001;
        cpu_write_en = 1;
        #100;
        cpu_write_en = 0;
        #100;

        $display("=== Test 3: Load input ===");
        cpu_control = 5;
        cpu_write_addr = 0;
        cpu_write_data = 16'h1234;
        cpu_write_en = 1;
        #100;
        cpu_write_en = 0;
        #100;

        $display("=== Test 4: Execute forward pass ===");
        cpu_opcode = 1;
        cpu_control = 20;
        #100;
        cpu_control = 0;
        #1000;

        $display("=== Test 5: Read result ===");
        cpu_control = 25;
        cpu_write_addr = 0;
        cpu_read_en = 1;
        #100;
        cpu_read_en = 0;
        #100;

        $display("=== All tests completed ===");
        $finish;
    end

    always @(posedge clk) begin
        cycle = cycle + 1;
        if (uut.control != 0 || uut.status != 0) begin
            $display("t=%0d: control=%d, status=%d, calc_phase=%d, calc_index=%d",
                     cycle, uut.control, uut.status, uut.calc_phase, uut.calc_index);
        end
    end

endmodule
