`timescale 1ns / 1ps

module iir_filter (
    input wire clk,
    input wire rst,
    input wire signed [15:0] x_in,
    output reg signed [15:0] y_out
);

    localparam signed [39:0] B0 =  3947;
    localparam signed [39:0] B1 = -7894;
    localparam signed [39:0] B2 =  3947;
    localparam signed [39:0] A2 = -7891; 
    localparam signed [39:0] A3 =  3801;

    reg signed [39:0] z1;
    reg signed [39:0] z2;

    wire signed [39:0] x_ext;
    wire signed [39:0] b0_x, b1_x, b2_x;
    wire signed [39:0] a2_y, a3_y;
    wire signed [39:0] y_acc;
    
    assign x_ext = {{24{x_in[15]}}, x_in};

    assign b0_x = x_ext * B0;
    assign b1_x = x_ext * B1;
    assign b2_x = x_ext * B2;

    assign y_acc = b0_x + z1;

    reg signed [15:0] y_comb;
    wire signed [39:0] y_scaled = y_acc >>> 12; 

    always @(*) begin
        if (y_scaled > 32767)      
            y_comb = 32767;
        else if (y_scaled < -32768) 
            y_comb = -32768;
        else                        
            y_comb = y_scaled[15:0];
    end

    wire signed [39:0] y_comb_ext = {{24{y_comb[15]}}, y_comb};
    
    assign a2_y = y_comb_ext * A2;
    assign a3_y = y_comb_ext * A3;

    always @(posedge clk) begin
        if (rst) begin
            y_out <= 0;
            z1 <= 0;
            z2 <= 0;
        end else begin
            y_out <= y_comb;
            z1 <= b1_x - a2_y + z2;
            z2 <= b2_x - a3_y;
        end
    end

endmodule