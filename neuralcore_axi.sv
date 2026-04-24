module neuralcore_axi (
    input wire s_axi_aclk,
    input wire s_axi_aresetn,
    input wire [17:0] s_axi_awaddr,
    input wire [2:0] s_axi_awprot,
    input wire s_axi_awvalid,
    output logic s_axi_awready,
    input wire [31:0] s_axi_wdata,
    input wire [3:0] s_axi_wstrb,
    input wire s_axi_wvalid,
    output logic s_axi_wready,
    output logic [1:0] s_axi_bresp,
    output logic s_axi_bvalid,
    input wire s_axi_bready,
    input wire [17:0] s_axi_araddr,
    input wire [2:0] s_axi_arprot,
    input wire s_axi_arvalid,
    output logic s_axi_arready,
    output logic [31:0] s_axi_rdata,
    output logic [1:0] s_axi_rresp,
    output logic s_axi_rvalid,
    input wire s_axi_rready
);

    logic [7:0] cpu_control;
    logic [3:0] cpu_opcode;
    logic [15:0] cpu_token_count;
    logic signed [15:0] cpu_write_data;
    logic [17:0] cpu_write_addr;
    logic cpu_write_en;
    logic cpu_read_en;
    logic [7:0] status;
    logic signed [15:0] read_data;

    neuralcore core_inst (
        .clk(s_axi_aclk),
        .rst_n(s_axi_aresetn),
        .cpu_control(cpu_control),
        .status(status),
        .cpu_opcode(cpu_opcode),
        .cpu_token_count(cpu_token_count),
        .cpu_write_data(cpu_write_data),
        .cpu_write_addr(cpu_write_addr),
        .cpu_write_en(cpu_write_en),
        .cpu_read_en(cpu_read_en),
        .read_data(read_data)
    );

    // AXI WRITE CHANNEL
    always_ff @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            s_axi_awready <= 0; s_axi_wready <= 0; s_axi_bvalid <= 0;
            cpu_write_en <= 0; cpu_control <= 0;
        end else begin
            cpu_write_en <= 0;
            if (~s_axi_awready && s_axi_awvalid && s_axi_wvalid) begin
                s_axi_awready <= 1; s_axi_wready <= 1;
                case (s_axi_awaddr[7:0])
                    8'h00: cpu_control     <= s_axi_wdata[7:0];
                    8'h08: cpu_opcode      <= s_axi_wdata[3:0];
                    8'h0C: cpu_token_count <= s_axi_wdata[15:0];
                    8'h40: cpu_write_data  <= s_axi_wdata[15:0];
                    8'h44: cpu_write_addr  <= s_axi_wdata[17:0];
                    8'h48: cpu_write_en    <= s_axi_wdata[0];
                    8'h4C: cpu_read_en     <= s_axi_wdata[0];
                endcase
            end else begin
                s_axi_awready <= 0; s_axi_wready <= 0;
            end

            if (s_axi_awready && s_axi_wvalid && ~s_axi_bvalid) begin
                s_axi_bvalid <= 1;
                s_axi_bresp <= 2'b00;
            end else if (s_axi_bready && s_axi_bvalid) begin
                s_axi_bvalid <= 0;
            end
        end
    end

    // AXI READ CHANNEL
    always_ff @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            s_axi_arready <= 0; s_axi_rvalid <= 0; s_axi_rdata <= 0;
        end else begin
            if (~s_axi_arready && s_axi_arvalid) begin
                s_axi_arready <= 1; s_axi_rvalid <= 1;
                case (s_axi_araddr[7:0])
                    8'h00: s_axi_rdata <= {24'h0, cpu_control};
                    8'h04: s_axi_rdata <= {24'h0, status};
                    8'h50: s_axi_rdata <= {16'h0, read_data};
                    default: s_axi_rdata <= 0;
                endcase
            end else if (s_axi_rready && s_axi_rvalid) begin
                s_axi_rvalid <= 0; s_axi_arready <= 0;
            end
        end
    end
endmodule