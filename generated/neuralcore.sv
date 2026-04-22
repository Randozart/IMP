// IMP Generated Hardware - SystemVerilog output (auto-generated, do not edit)
//     Copyright (C) 2026 Randy Smits-Schreuder Goedheijt
//
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
    logic signed [15:0] kv_cache_k [0:262143] /* synthesis keep */;
    logic signed [15:0] kv_cache_v [0:262143] /* synthesis keep */;
    logic signed [15:0] input_embedding [0:262143] /* synthesis syn_ramstyle = "block_ram" */ /* synthesis keep */;
    logic signed [15:0] output_logits [0:262143] /* synthesis syn_ramstyle = "block_ram" */ /* synthesis keep */;
    logic signed [15:0] mlp_gate [0:262143] /* synthesis syn_ramstyle = "block_ram" */ /* synthesis keep */;
    logic signed [15:0] mlp_up [0:262143] /* synthesis syn_ramstyle = "block_ram" */ /* synthesis keep */;
    logic signed [15:0] mlp_down [0:262143] /* synthesis syn_ramstyle = "block_ram" */ /* synthesis keep */;
    logic signed [15:0] attention_qkv [0:262143] /* synthesis syn_ramstyle = "block_ram" */ /* synthesis keep */;
    logic signed [15:0] attention_out [0:262143] /* synthesis syn_ramstyle = "block_ram" */ /* synthesis keep */;
    logic signed [15:0] embedding_table [0:262143] /* synthesis syn_ramstyle = "block_ram" */ /* synthesis keep */;
    logic signed [15:0] scratch [0:262143] /* synthesis syn_ramstyle = "block_ram" */ /* synthesis keep */;
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
            else if (((calc_phase == 1) && (calc_index < 262144))) begin
                calc_index <= (calc_index + 1);
            end
            else if (((calc_phase == 2) && (calc_index < 262144))) begin
                calc_index <= (calc_index + 1);
            end
            else if (((calc_phase == 2) && (calc_index >= 262144))) begin
                calc_index <= 0;
            end
            else if (((calc_phase == 3) && (calc_index < 262144))) begin
                calc_index <= (calc_index + 1);
            end
            else if (((calc_phase == 3) && (calc_index >= 262144))) begin
                calc_index <= 0;
            end
            else if (((calc_phase == 4) && (calc_index < 262144))) begin
                calc_index <= (calc_index + 1);
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
            else if (((calc_phase == 1) && (calc_index < 262144))) begin
                acc_result <= (acc_result + current_input);
            end
            else if (((calc_phase == 2) && (calc_index < 262144))) begin
                acc_result <= (acc_result + current_input);
            end
            else if (((calc_phase == 3) && (calc_index < 262144))) begin
                acc_result <= (acc_result + current_input);
            end
            else if (((calc_phase == 4) && (calc_index < 262144))) begin
                acc_result <= (acc_result + current_input);
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
            if (((calc_phase == 1) && (calc_index < 262144))) begin
                current_input <= input_embedding[calc_index];
            end
            else if (((calc_phase == 2) && (calc_index < 262144))) begin
                current_input <= input_embedding[calc_index];
            end
            else if (((calc_phase == 3) && (calc_index < 262144))) begin
                current_input <= input_embedding[calc_index];
            end
            else if (((calc_phase == 4) && (calc_index < 262144))) begin
                current_input <= (scratch[0] + scratch[1]);
            end
        end
    end

    // Logic for variable: current_weight
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            current_weight <= 0;
        end else begin
            if (((calc_phase == 1) && (calc_index < 262144))) begin
                current_weight <= attention_qkv[calc_index];
            end
            else if (((calc_phase == 2) && (calc_index < 262144))) begin
                current_weight <= mlp_gate[calc_index];
            end
            else if (((calc_phase == 3) && (calc_index < 262144))) begin
                current_weight <= mlp_up[calc_index];
            end
            else if (((calc_phase == 4) && (calc_index < 262144))) begin
                current_weight <= mlp_down[calc_index];
            end
        end
    end

    // Logic for variable: kv_cache_k
    // RAM template for kv_cache_k (type: Some("ultraram"), size: 262144)
    always_ff @(posedge clk) begin
        // No reset initialization needed - BRAM auto-initializes on power-up
        if ((cpu_write_en && (control == 3))) begin
                    kv_cache_k[cpu_write_addr] <= cpu_write_data;
        end
    end

    // Logic for variable: kv_cache_v
    // RAM template for kv_cache_v (type: Some("ultraram"), size: 262144)
    always_ff @(posedge clk) begin
        // No reset initialization needed - BRAM auto-initializes on power-up
        if ((cpu_write_en && (control == 4))) begin
                    kv_cache_v[cpu_write_addr] <= cpu_write_data;
        end
    end

    // Logic for variable: input_embedding
    // RAM template for input_embedding (type: Some("bram"), size: 262144)
    always_ff @(posedge clk) begin
        // No reset initialization needed - BRAM auto-initializes on power-up
        if ((cpu_write_en && (control == 5))) begin
                    input_embedding[cpu_write_addr] <= cpu_write_data;
        end
    end

    // Logic for variable: output_logits
    // RAM template for output_logits (type: Some("bram"), size: 262144)
    always_ff @(posedge clk) begin
        // No reset initialization needed - BRAM auto-initializes on power-up
        if ((cpu_write_en && (control == 6))) begin
                    output_logits[cpu_write_addr] <= cpu_write_data;
        end
        else if (((calc_phase == 1) && (calc_index >= 262144))) begin
                    output_logits[0] <= acc_result;
        end
        else if (((calc_phase == 4) && (calc_index >= 262144))) begin
                    output_logits[0] <= acc_result;
        end
    end

    // Logic for variable: mlp_gate
    // RAM template for mlp_gate (type: Some("bram"), size: 262144)
    always_ff @(posedge clk) begin
        // No reset initialization needed - BRAM auto-initializes on power-up
        if ((cpu_write_en && (control == 10))) begin
                    mlp_gate[cpu_write_addr] <= cpu_write_data;
        end
    end

    // Logic for variable: mlp_up
    // RAM template for mlp_up (type: Some("bram"), size: 262144)
    always_ff @(posedge clk) begin
        // No reset initialization needed - BRAM auto-initializes on power-up
        if ((cpu_write_en && (control == 11))) begin
                    mlp_up[cpu_write_addr] <= cpu_write_data;
        end
    end

    // Logic for variable: mlp_down
    // RAM template for mlp_down (type: Some("bram"), size: 262144)
    always_ff @(posedge clk) begin
        // No reset initialization needed - BRAM auto-initializes on power-up
        if ((cpu_write_en && (control == 12))) begin
                    mlp_down[cpu_write_addr] <= cpu_write_data;
        end
    end

    // Logic for variable: attention_qkv
    // RAM template for attention_qkv (type: Some("bram"), size: 262144)
    always_ff @(posedge clk) begin
        // No reset initialization needed - BRAM auto-initializes on power-up
        if ((cpu_write_en && (control == 13))) begin
                    attention_qkv[cpu_write_addr] <= cpu_write_data;
        end
    end

    // Logic for variable: attention_out
    // RAM template for attention_out (type: Some("bram"), size: 262144)
    always_ff @(posedge clk) begin
        // No reset initialization needed - BRAM auto-initializes on power-up
        if ((cpu_write_en && (control == 14))) begin
                    attention_out[cpu_write_addr] <= cpu_write_data;
        end
    end

    // Logic for variable: embedding_table
    // RAM template for embedding_table (type: Some("bram"), size: 262144)
    always_ff @(posedge clk) begin
        // No reset initialization needed - BRAM auto-initializes on power-up
        if ((cpu_write_en && (control == 15))) begin
                    embedding_table[cpu_write_addr] <= cpu_write_data;
        end
    end

    // Logic for variable: scratch
    // RAM template for scratch (type: Some("bram"), size: 262144)
    always_ff @(posedge clk) begin
        // No reset initialization needed - BRAM auto-initializes on power-up
        if (((calc_phase == 2) && (calc_index >= 262144))) begin
                    scratch[0] <= acc_result;
        end
        else if (((calc_phase == 3) && (calc_index >= 262144))) begin
                    scratch[1] <= acc_result;
        end
    end

    // Logic for variable: read_data
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            read_data <= 0;
        end else begin
            if ((cpu_read_en && (control == 25))) begin
                read_data <= output_logits[cpu_write_addr];
            end
        end
    end

endmodule
