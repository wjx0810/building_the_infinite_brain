`timescale 1ns / 1ps

module spike_detect (
    input wire clk,
    input wire rst,
    input wire signed [15:0] data_in,
    input wire signed [15:0] threshold,
    output reg spike_out
);

    // Lockout duration 20 samples
    localparam integer LOCKOUT = 20;
    // Artifact rejection
    localparam signed [15:0] SATURATION_NEG = -16'd30000;

    reg [4:0] timer;

    always @(posedge clk) begin
        if (rst) begin
            spike_out <= 0;
            timer <= 0;
        end else begin
            spike_out <= 0;

            if (timer > 0) begin
                // If lockout active, decrement timer and ignore input
                timer <= timer - 1;
            end else begin
                // Spike detection logic
                if ((data_in < threshold) && (data_in > SATURATION_NEG)) begin
                    spike_out <= 1;
                    timer <= LOCKOUT;
                end
            end
        end
    end

endmodule