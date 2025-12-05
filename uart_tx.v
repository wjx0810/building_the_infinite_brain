`timescale 1ns / 1ps

module uart_tx (
    input wire clk,       // 100MHz System Clock
    input wire rst,
    input wire start,     // Pulse to start transmission
    input wire [7:0] data,// Byte to send
    output reg tx_line,   // Serial Output
    output reg busy       // High while sending
);

    // Baud Rate Generator
    // 100MHz / 115200 baud = 868 clocks per bit
    localparam CLKS_PER_BIT = 868;
    
    reg [2:0] state;
    localparam s_IDLE = 0;
    localparam s_START = 1;
    localparam s_DATA = 2;
    localparam s_STOP = 3;

    reg [15:0] clk_cnt;
    reg [2:0] bit_idx;
    reg [7:0] data_shifter;

    always @(posedge clk) begin
        if (rst) begin
            state <= s_IDLE;
            tx_line <= 1; // Idle High
            busy <= 0;
            clk_cnt <= 0;
            bit_idx <= 0;
        end else begin
            case (state)
                // Wait for start signal
                s_IDLE: begin
                    tx_line <= 1;
                    busy <= 0;
                    clk_cnt <= 0;
                    bit_idx <= 0;
                    if (start) begin
                        state <= s_START;
                        busy <= 1;
                        data_shifter <= data;
                    end
                end

                // Start Bit (Low)
                s_START: begin
                    tx_line <= 0;
                    if (clk_cnt < CLKS_PER_BIT-1) begin
                        clk_cnt <= clk_cnt + 1;
                    end else begin
                        clk_cnt <= 0;
                        state <= s_DATA;
                    end
                end

                // 8 Data Bits
                s_DATA: begin
                    tx_line <= data_shifter[bit_idx];
                    if (clk_cnt < CLKS_PER_BIT-1) begin
                        clk_cnt <= clk_cnt + 1;
                    end else begin
                        clk_cnt <= 0;
                        if (bit_idx < 7) begin
                            bit_idx <= bit_idx + 1;
                        end else begin
                            bit_idx <= 0;
                            state <= s_STOP;
                        end
                    end
                end

                // Stop Bit (High)
                s_STOP: begin
                    tx_line <= 1;
                    if (clk_cnt < CLKS_PER_BIT-1) begin
                        clk_cnt <= clk_cnt + 1;
                    end else begin
                        state <= s_IDLE; // Done
                    end
                end
            endcase
        end
    end
endmodule