`timescale 1ns / 1ps

module tb_pipeline();
    reg clk;
    reg rst;
    reg signed [15:0] raw_in;
    wire signed [15:0] vel_out;

    integer file, status, watchdog;
    reg signed [15:0] file_data;

    // Top module
    neural_pipeline_top uut (
        .clk(clk), 
        .rst(rst),
        .raw_in(raw_in),
        .vel_out(vel_out)
    );

    // Clock generation
    initial begin
        clk = 0;
        forever #16666 clk = ~clk; 
    end

    initial begin
        file = $fopen("test_vector.txt", "r"); 
        if (file == 0) begin
            $display("Error: Could not open test_vector.txt");
            $finish;
        end

        rst = 1;
        raw_in = 0;
        watchdog = 0;

        // Reset
        #100000;
        rst = 0;

        // Read loop
        while (!$feof(file) && watchdog < 1600000) begin
            @(posedge clk); 
            status = $fscanf(file, "%d\n", file_data); 
            
            if (status == 1) begin
                raw_in = file_data;
            end
            watchdog = watchdog + 1;
        end

        $fclose(file);
        $display("Simulation Finished. Processed %d samples.", watchdog);
        $finish;
    end
endmodule