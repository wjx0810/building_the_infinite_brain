`timescale 1ns / 1ps

module neural_pipeline_top (
    input wire clk,
    input wire rst,
    input wire signed [15:0] raw_in,
    output wire signed [15:0] vel_out
);
    wire signed [15:0] filt_out;
    wire spike_pulse_raw; // Output from detector
    reg spike_pulse_safe; // Gated signal after warmup
    
    // Auto-calculated threshold
    wire signed [15:0] auto_threshold;

    // Warmup
    reg [17:0] warmup_cnt; 
    
    always @(posedge clk) begin
        if (rst) begin
            warmup_cnt <= 0;
            spike_pulse_safe <= 0;
        end else begin
            // Count up to 150,000 then stop
            if (warmup_cnt < 150000) 
                warmup_cnt <= warmup_cnt + 1;
            
            // Only pass spikes if warmup is done
            if (warmup_cnt == 150000) 
                spike_pulse_safe <= spike_pulse_raw;
            else 
                spike_pulse_safe <= 0;
        end
    end
    // Binning
    reg [10:0] bin_timer;
    reg bin_strobe;
    reg signed [15:0] bin_accumulator;
    reg signed [15:0] current_bin_count;

    // HP filter
    iir_filter u_filter (
        .clk(clk),
        .rst(rst),
        .x_in(raw_in),
        .y_out(filt_out)
    );
    
    // Threshold estimator
    threshold_estimator u_thresh_gen (
        .clk(clk),
        .rst(rst),
        .data_in(filt_out),
        .threshold(auto_threshold)
    );

    // Spike detector
    spike_detect u_detect (
        .clk(clk),
        .rst(rst),
        .data_in(filt_out),
        .threshold(auto_threshold), 
        .spike_out(spike_pulse_raw) 
    );

    // Binning
    always @(posedge clk) begin
        if (rst) begin
            bin_timer <= 0;
            bin_accumulator <= 0;
            current_bin_count <= 0;
            bin_strobe <= 0;
        end else begin
            bin_strobe <= 0;
            
            // Accumulate safe spikes
            if (spike_pulse_safe)
                bin_accumulator <= bin_accumulator + 1;

            if (bin_timer == 1499) begin
                bin_timer <= 0;
                current_bin_count <= bin_accumulator;
                bin_accumulator <= 0;
                bin_strobe <= 1;
            end else begin
                bin_timer <= bin_timer + 1;
                bin_strobe <= 0;
            end
        end
    end

    // Velocity decoder
    velocity_decoder u_decoder (
        .clk(clk),
        .rst(rst),
        .bin_strobe(bin_strobe),
        .bin_count(current_bin_count),
        .velocity(vel_out)
    );

endmodule