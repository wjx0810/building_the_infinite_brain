`timescale 1ns / 1ps

module threshold_estimator (
    input wire clk,
    input wire rst,
    input wire signed [15:0] data_in,
    output reg signed [15:0] threshold
);
    // Calculate absolute value
    reg signed [15:0] abs_data;
    always @(*) begin
        if (data_in == -16'd32768) abs_data = 16'd32767;
        else abs_data = (data_in < 0) ? -data_in : data_in;
    end

    // Leaky integrator
    localparam K = 14; 
    reg signed [31:0] accumulator;
    
    always @(posedge clk) begin
        if (rst) begin
            accumulator <= 0;
            threshold <= 0;
        end else begin
            // Update estimate
            accumulator <= accumulator - (accumulator >>> K) + abs_data;
            
            // Calculate thresehold
            threshold <= -(((accumulator >>> K) * 45) >>> 3);
        end
    end
endmodule