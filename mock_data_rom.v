`timescale 1ns / 1ps

module mock_data_rom (
    input wire clk, 
    output reg [15:0] data_out 
);

    reg signed [15:0] internal_signal;

    // 32-bit LFSR
    reg [31:0] lfsr = 32'hACE12345;
    wire feedback = lfsr[31] ^ lfsr[21] ^ lfsr[1] ^ lfsr[0];
    
    always @(posedge clk) begin
        lfsr <= {lfsr[30:0], feedback};
    end

    // AWGN
    reg signed [15:0] noise_gauss;
    always @(*) begin
        noise_gauss = ($signed({1'b0, lfsr[4:0]}) - 16) + 
                      ($signed({1'b0, lfsr[9:5]}) - 16) + 
                      ($signed({1'b0, lfsr[14:10]}) - 16) + 
                      ($signed({1'b0, lfsr[19:15]}) - 16);
        noise_gauss = noise_gauss * 16; 
    end

    // LFP
    reg [5:0] lfp_idx = 0;
    reg [7:0] lfp_timer = 0;
    reg signed [15:0] lfp_val;
    
    always @(*) begin
        case(lfp_idx)
            0: lfp_val = 0;   8: lfp_val = 707;  16: lfp_val = 1000; 24: lfp_val = 707;
            32: lfp_val = 0; 40: lfp_val = -707; 48: lfp_val = -1000; 56: lfp_val = -707;
            default: begin
                if (lfp_idx < 16) lfp_val = 500;
                else if (lfp_idx < 32) lfp_val = 500; 
                else if (lfp_idx < 48) lfp_val = -500;
                else lfp_val = -500;
            end
        endcase
    end
    
    always @(posedge clk) begin
        lfp_timer <= lfp_timer + 1;
        if (lfp_timer == 0) lfp_idx <= lfp_idx + 1;
    end

    // Spike playback
    reg [4:0] spike_idx = 0; 
    reg signed [15:0] spike_val;
    
    always @(*) begin
        case(spike_idx)
            1: spike_val = 200;    2: spike_val = 500;
            3: spike_val = -2000;  4: spike_val = -10000;
            5: spike_val = -20000; 6: spike_val = -15000; 7: spike_val = -5000;
            8: spike_val = 3000;   9: spike_val = 5000;   10: spike_val = 3000;
            11: spike_val = 1000;  12: spike_val = 500;
            13: spike_val = 0;
            default: spike_val = 0;
        endcase
    end
    
    reg [31:0] sample_cnt = 0;
    
    always @(posedge clk) begin
        sample_cnt <= sample_cnt + 1;
        
        if (spike_idx == 0) begin
            if (lfsr[15:0] < 54 && sample_cnt > 1500) begin
                spike_idx <= 1;
            end
        end else begin
            if (spike_idx == 13) spike_idx <= 0;
            else spike_idx <= spike_idx + 1;
        end
    end

    // Convert signed to unsigned binary
    always @(posedge clk) begin
        internal_signal <= lfp_val + spike_val + noise_gauss;
        
        // This simulates what comes out of a real ADC chip
        data_out <= { ~internal_signal[15], internal_signal[14:0] };
    end

endmodule