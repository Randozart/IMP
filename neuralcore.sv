module neuralcore (
    input logic clk,
    input logic rst_n
);

    logic [7:0] cpu_control;
    logic [7:0] cpu_status;
    logic [3:0] cpu_opcode;
    logic [15:0] cpu_token_count;
    logic signed [15:0] cpu_write_data;
    logic [17:0] cpu_write_addr;
    logic  cpu_write_en;
    logic  cpu_read_en;
    logic [7:0] control;
    logic [7:0] status;
    logic [3:0] opcode;
    logic [31:0] calc_index;
    logic [31:0] calc_phase;
    logic signed [31:0] acc_result;
    logic signed [31:0] current_input;
    logic signed [31:0] current_weight;
    logic signed [15:0] weight_buffer [0:262143] /* synthesis syn_ramstyle = "block_ram" */ /* synthesis keep */;
    logic signed [15:0] scratch [0:262143] /* synthesis keep */;
    logic signed [15:0] read_data;

    // Logic for variable: control
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            control <= 0;
        end else begin
            if ((cpu_control != control)) begin
                control <= cpu_control;
            end
            else if ((control == 0)) begin
                control <= 0;
            end
        end
    end

    // Logic for variable: status
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            status <= 0;
        end else begin
            if ((status == 5)) begin
                status <= 2;
            end
            else if ((control == 0)) begin
                status <= 0;
            end
        end
    end

    // Logic for variable: opcode
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            opcode <= 0;
        end else begin
            if ((cpu_control != control)) begin
                opcode <= cpu_opcode;
            end
            else if ((control == 0)) begin
                opcode <= 0;
            end
        end
    end

    // Logic for variable: calc_index
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            calc_index <= 0;
        end else begin
            if (((control == 20) && (status == 0))) begin
                calc_index <= 0;
            end
            else if ((((calc_phase >= 1) && (calc_phase <= 4)) && (calc_index < 262144))) begin
                if ((current_weight == 1)) begin
                end
                if ((current_weight == /* Unsupported Expr: Neg(Integer(1)) */)) begin
                end
                if ((current_weight == 0)) begin
                end
                calc_index <= (calc_index + 1);
            end
            else if (((calc_phase == 1) && (calc_index >= 262144))) begin
                calc_index <= 0;
            end
            else if (((calc_phase == 2) && (calc_index >= 262144))) begin
                calc_index <= 0;
            end
            else if (((calc_phase == 3) && (calc_index >= 262144))) begin
                calc_index <= 0;
            end
            else if (((calc_phase == 4) && (calc_index >= 262144))) begin
                calc_index <= 0;
            end
            else if ((control == 0)) begin
                calc_index <= 0;
            end
        end
    end

    // Logic for variable: calc_phase
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            calc_phase <= 0;
        end else begin
            if (((control == 20) && (status == 0))) begin
                calc_phase <= opcode;
            end
            else if (((calc_phase == 1) && (calc_index >= 262144))) begin
                calc_phase <= 0;
            end
            else if (((calc_phase == 2) && (calc_index >= 262144))) begin
                calc_phase <= 0;
            end
            else if (((calc_phase == 3) && (calc_index >= 262144))) begin
                calc_phase <= 0;
            end
            else if (((calc_phase == 4) && (calc_index >= 262144))) begin
                calc_phase <= 0;
            end
            else if ((control == 0)) begin
                calc_phase <= 0;
            end
        end
    end

    // Logic for variable: acc_result
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            acc_result <= 0;
        end else begin
            if (((control == 20) && (status == 0))) begin
                acc_result <= 0;
            end
            else if ((((calc_phase >= 1) && (calc_phase <= 4)) && (calc_index < 262144))) begin
                if ((current_weight == 1)) begin
                acc_result <= (acc_result + current_input);
                end
                if ((current_weight == /* Unsupported Expr: Neg(Integer(1)) */)) begin
                acc_result <= (acc_result - current_input);
                end
                if ((current_weight == 0)) begin
                acc_result <= (acc_result + 0);
                end
            end
            else if ((control == 0)) begin
                acc_result <= 0;
            end
        end
    end

    // Logic for variable: current_input
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            current_input <= 0;
        end else begin
            if ((((calc_phase >= 1) && (calc_phase <= 4)) && (calc_index < 262144))) begin
                current_input <= scratch[calc_index];
                if ((current_weight == 1)) begin
                end
                if ((current_weight == /* Unsupported Expr: Neg(Integer(1)) */)) begin
                end
                if ((current_weight == 0)) begin
                end
            end
        end
    end

    // Logic for variable: current_weight
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            current_weight <= 0;
        end else begin
            if ((((calc_phase >= 1) && (calc_phase <= 4)) && (calc_index < 262144))) begin
                current_weight <= weight_buffer[calc_index];
                if ((current_weight == 1)) begin
                end
                if ((current_weight == /* Unsupported Expr: Neg(Integer(1)) */)) begin
                end
                if ((current_weight == 0)) begin
                end
            end
        end
    end

    // Logic for variable: weight_buffer
    // RAM template for weight_buffer (type: Some("bram"), size: 262144)
    always_ff @(posedge clk) begin
        // No reset initialization needed - BRAM auto-initializes on power-up
        if ((cpu_write_en && (control == 1))) begin
                    weight_buffer[cpu_write_addr] <= cpu_write_data;
        end
    end

    // Logic for variable: scratch
    // RAM template for scratch (type: Some("ultraram"), size: 262144)
    always_ff @(posedge clk) begin
        // No reset initialization needed - BRAM auto-initializes on power-up
        if ((cpu_write_en && (control == 5))) begin
                    scratch[cpu_write_addr] <= cpu_write_data;
        end
        else if (((calc_phase == 1) && (calc_index >= 262144))) begin
                    scratch[0] <= acc_result;
        end
        else if (((calc_phase == 2) && (calc_index >= 262144))) begin
                    scratch[1] <= acc_result;
        end
        else if (((calc_phase == 3) && (calc_index >= 262144))) begin
                    scratch[2] <= acc_result;
        end
        else if (((calc_phase == 4) && (calc_index >= 262144))) begin
                    scratch[3] <= acc_result;
        end
        else if ((cpu_write_en && (control == 3))) begin
                    scratch[cpu_write_addr] <= cpu_write_data;
        end
        else if ((cpu_write_en && (control == 4))) begin
                    scratch[cpu_write_addr] <= cpu_write_data;
        end
    end

    // Logic for variable: read_data
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            read_data <= 0;
        end else begin
            if ((cpu_read_en && (control == 25))) begin
                read_data <= scratch[cpu_write_addr];
            end
        end
    end

endmodule
