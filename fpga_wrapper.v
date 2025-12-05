`timescale 1ns / 1ps

module fpga_wrapper(
    input wire CLK100MHZ,    
    input wire CPU_RESETN,   
    output wire [15:0] LED,
    output wire UART_TXD     
    );

    // Clock generation
    reg [15:0] clk_cnt;
    reg clk_30khz;
    wire sys_rst = ~CPU_RESETN;

    always @(posedge CLK100MHZ) begin
        if (sys_rst) begin
            clk_cnt <= 0;
            clk_30khz <= 0;
        end else begin
            if (clk_cnt >= 1666) begin
                clk_cnt <= 0;
                clk_30khz <= ~clk_30khz;
            end else begin
                clk_cnt <= clk_cnt + 1;
            end
        end
    end

    // Data generation
    wire [15:0] adc_unsigned_data; 
    mock_data_rom u_patient (
        .clk(clk_30khz), 
        .data_out(adc_unsigned_data)
    );

    // Unsigned to signed two's complement conversion
    wire signed [15:0] pipeline_input_signed;
    assign pipeline_input_signed = { ~adc_unsigned_data[15], adc_unsigned_data[14:0] };

    // Neural pipeline
    wire signed [15:0] vel_result;
    neural_pipeline_top u_pipeline (
        .clk(clk_30khz),
        .rst(sys_rst),
        .raw_in(pipeline_input_signed), 
        .vel_out(vel_result)
    );
    assign LED = vel_result;

    // UART
    reg [15:0] vel_prev;
    reg trig_send;
    
    always @(posedge CLK100MHZ) begin
        if (sys_rst) begin
            vel_prev <= 0;
            trig_send <= 0;
        end else begin
            if (vel_result != vel_prev) begin
                vel_prev <= vel_result;
                trig_send <= 1; 
            end else begin
                trig_send <= 0;
            end
        end
    end

    // State Machine
    reg [4:0] state;
    reg [7:0] uart_byte;
    reg uart_start;
    wire uart_busy;
    
    // Math
    reg [15:0] abs_val;
    reg is_neg;
    reg [3:0] int_part;      // Integer part (0-5)
    reg [11:0] raw_frac;     // Lower 12 bits
    reg [25:0] calc_frac;    // Large register for multiplication (4095 * 10000)
    reg [13:0] final_frac;   // Result (0-9999)
    
    reg [3:0] d3, d2, d1, d0; // 4 decimal points
    
    localparam S_IDLE = 0;
    localparam S_MATH_1 = 1; // Abs and Split
    localparam S_MATH_2 = 2; // Multiply fraction
    localparam S_MATH_3 = 3; // Shift and split digits
    localparam S_SIGN = 4;
    localparam S_SIGN_W = 5;
    localparam S_INT = 6;
    localparam S_INT_W  = 7;
    localparam S_DOT = 8;
    localparam S_DOT_W = 9;
    localparam S_F3 = 10;
    localparam S_F3_W = 11;
    localparam S_F2 = 12;
    localparam S_F2_W = 13;
    localparam S_F1 = 14;
    localparam S_F1_W = 15;
    localparam S_F0 = 16;
    localparam S_F0_W = 17;
    localparam S_CR = 18;
    localparam S_CR_W = 19;
    localparam S_LF = 20;
    localparam S_LF_W = 21;

    always @(posedge CLK100MHZ) begin
        if (sys_rst) begin
            state <= S_IDLE;
            uart_start <= 0;
        end else begin
            case (state)
                S_IDLE: begin
                    uart_start <= 0;
                    if (trig_send) begin
                        is_neg <= vel_prev[15];
                        if (vel_prev[15]) abs_val <= -vel_prev;
                        else abs_val <= vel_prev;
                        state <= S_MATH_1;
                    end
                end
                
                // Separate int and decimal
                S_MATH_1: begin
                    int_part <= abs_val[15:12]; // Top 4 bits
                    raw_frac <= abs_val[11:0];  // Bottom 12 bits
                    state <= S_MATH_2;
                end

                // Scale decimal
                S_MATH_2: begin
                    calc_frac <= raw_frac * 16'd10000; 
                    state <= S_MATH_3;
                end
                
                // Shift by 12
                S_MATH_3: begin
                    final_frac = calc_frac[25:12]; 
                    
                    // Extract digits
                    d3 <= (final_frac / 1000) % 10;
                    d2 <= (final_frac / 100) % 10;
                    d1 <= (final_frac / 10) % 10;
                    d0 <= final_frac % 10;
                    
                    state <= S_SIGN;
                end

                // Print sign
                S_SIGN: begin uart_byte <= is_neg ? "-" : "+"; uart_start <= 1; state <= S_SIGN_W; end
                S_SIGN_W: begin uart_start <= 0; if (uart_busy) state <= 22; end

                // Int
                S_INT: begin uart_byte <= 8'h30 + int_part; uart_start <= 1; state <= S_INT_W; end
                S_INT_W: begin uart_start <= 0; if (uart_busy) state <= 23; end

                // Decimal point
                S_DOT: begin uart_byte <= "."; uart_start <= 1; state <= S_DOT_W; end
                S_DOT_W: begin uart_start <= 0; if (uart_busy) state <= 24; end
                
                // Fraction
                S_F3: begin uart_byte <= 8'h30 + d3; uart_start <= 1; state <= S_F3_W; end
                S_F3_W: begin uart_start <= 0; if (uart_busy) state <= 25; end
                S_F2: begin uart_byte <= 8'h30 + d2; uart_start <= 1; state <= S_F2_W; end
                S_F2_W: begin uart_start <= 0; if (uart_busy) state <= 26; end
                S_F1: begin uart_byte <= 8'h30 + d1; uart_start <= 1; state <= S_F1_W; end
                S_F1_W: begin uart_start <= 0; if (uart_busy) state <= 27; end
                S_F0: begin uart_byte <= 8'h30 + d0; uart_start <= 1; state <= S_F0_W; end
                S_F0_W: begin uart_start <= 0; if (uart_busy) state <= 28; end
                
                // New Line
                S_CR: begin uart_byte <= 8'h0D; uart_start <= 1; state <= S_CR_W; end
                S_CR_W: begin uart_start <= 0; if (uart_busy) state <= 29; end
                S_LF: begin uart_byte <= 8'h0A; uart_start <= 1; state <= S_LF_W; end
                S_LF_W: begin uart_start <= 0; if (uart_busy) state <= 30; end

                // Wait Anchors
                22: if (!uart_busy) state <= S_INT;
                23: if (!uart_busy) state <= S_DOT;
                24: if (!uart_busy) state <= S_F3;
                25: if (!uart_busy) state <= S_F2;
                26: if (!uart_busy) state <= S_F1;
                27: if (!uart_busy) state <= S_F0;
                28: if (!uart_busy) state <= S_CR;
                29: if (!uart_busy) state <= S_LF;
                30: if (!uart_busy) state <= S_IDLE;
            endcase
        end
    end

    uart_tx u_tx (
        .clk(CLK100MHZ),
        .rst(sys_rst),
        .start(uart_start),
        .data(uart_byte),
        .tx_line(UART_TXD),
        .busy(uart_busy)
    );

endmodule