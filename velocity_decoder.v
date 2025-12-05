module velocity_decoder (
    input wire clk,
    input wire rst,
    input wire bin_strobe, // Trigger every 50ms
    input wire signed [15:0] bin_count, // Number of spikes
    output reg signed [15:0] velocity // Output Q4.12
);

    localparam signed [15:0] M1 = 16'd3891; // 0.95
    localparam signed [15:0] M2 = 16'd819; // 0.20
    
    // Safety limits (+/- 5.0)
    localparam signed [15:0] MAX_VEL = 16'd20480; 
    localparam signed [15:0] MIN_VEL = -16'd20480;

    reg signed [31:0] term1; // M1 * v (Q8.24)
    reg signed [31:0] term2; // M2 * bins (Q4.12)
    reg signed [31:0] sum; // Accumulator

    always @(posedge clk) begin
        if (rst) begin
            velocity <= 0;
        end else if (bin_strobe) begin
            // Calculate Q4.12 * Q4.12 = Q8.24
            term1 = velocity * M1; 
            
            // Integer * Q4.12 = Q4.12, left shift by 12 to match Q8.24 format
            term2 = (bin_count * M2) <<< 12;
            sum = term1 + term2;

            // Scale back and clip
            if ((sum >>> 12) > MAX_VEL) 
                velocity <= MAX_VEL;
            else if ((sum >>> 12) < MIN_VEL)
                velocity <= MIN_VEL;
            else
                velocity <= sum >>> 12;
        end
    end

endmodule