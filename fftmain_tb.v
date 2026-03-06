`timescale 1ns / 1ps

module fftmain_tb;

    // =========================================================
    // 1. CONFIGURATION
    // =========================================================
    localparam FFT_SIZE = 128;

    // =========================================================
    // 2. CONTROL SIGNALS
    // =========================================================
    reg clk = 0;
    reg i_reset = 1;
    reg i_ce = 0;

    // =========================================================
    // 3. FFT INTERFACE
    // =========================================================
    reg  [15:0] i_sample;
    wire [15:0] o_result;
    wire        o_sync;

    // Split FFT output
    wire signed [7:0] out_re = $signed(o_result[15:8]);
    wire signed [7:0] out_im = $signed(o_result[7:0]);

    // =========================================================
    // 4. TESTBENCH VARIABLES
    // =========================================================
    integer i;
    integer file_in;
    integer file_out;
    integer timeout_cnt;

    // Complex fixed-point input
    reg signed [7:0] in_re;
    reg signed [7:0] in_im;

    // =========================================================
    // 5. PACK FUNCTION
    // =========================================================
    function [15:0] pack_sample(
        input signed [7:0] re,
        input signed [7:0] im
    );
    begin
        pack_sample = {re, im};   // {REAL, IMAG}
    end
    endfunction

    // =========================================================
    // 6. DUT INSTANTIATION
    // =========================================================
    fftmain uut (
        .i_clk   (clk),
        .i_reset (i_reset),
        .i_ce    (i_ce),
        .i_sample(i_sample),
        .o_result(o_result),
        .o_sync  (o_sync)
    );

    // =========================================================
    // 7. CLOCK GENERATION (100 MHz)
    // =========================================================
    always #5 clk = ~clk;

    // =========================================================
    // 8. MAIN TEST SEQUENCE
    // =========================================================
    initial begin
        // -----------------------------------------------------
        // Open files
        // -----------------------------------------------------
        file_in  = $fopen("fft_input_complex.txt",  "w");
        file_out = $fopen("fft_output_complex.txt", "w");

        if (file_in == 0 || file_out == 0) begin
            $display("ERROR: Cannot open input/output file");
            $finish;
        end

        // -----------------------------------------------------
        // RESET
        // -----------------------------------------------------
        $display("Simulation start");
        i_reset  = 1;
        i_ce     = 0;
        i_sample = 0;

        #100;
        @(posedge clk);
        i_reset = 0;
        @(posedge clk);

        // -----------------------------------------------------
        // FEED FFT INPUT
        // -----------------------------------------------------
        $display("Feeding %0d complex samples", FFT_SIZE);
        i_ce = 1;

        for (i = 0; i < FFT_SIZE; i = i + 1) begin
            // Random complex fixed-point input
            in_re = $random % 128;
            in_im = $random % 128;

            // Pack into FFT input bus
            i_sample = pack_sample(in_re, in_im);

            // Log INPUT
            $fdisplay(file_in, "%4d %4d", in_re, in_im);

            @(posedge clk);
        end

        // Stop feeding input
        i_sample = 0;

        // -----------------------------------------------------
        // WAIT FOR FFT OUTPUT SYNC
        // -----------------------------------------------------
        timeout_cnt = 0;
        $display("Waiting for o_sync...");

        while (o_sync == 0 && timeout_cnt < 10000) begin
            @(posedge clk);
            timeout_cnt = timeout_cnt + 1;
        end

        if (timeout_cnt >= 10000) begin
            $display("ERROR: FFT timeout");
            $finish;
        end

        // -----------------------------------------------------
        // CAPTURE FFT OUTPUT
        // -----------------------------------------------------
        $display("Capturing FFT output");

        for (i = 0; i < FFT_SIZE; i = i + 1) begin
            $fdisplay(file_out, "%4d %4d", out_re, out_im);
            @(posedge clk);
        end

        // -----------------------------------------------------
        // FINISH
        // -----------------------------------------------------
        $display("----------------------------------");
        $display("Simulation finished successfully");
        $display("Input  saved to fft_input_complex.txt");
        $display("Output saved to fft_output_complex.txt");
        $display("----------------------------------");

        $fclose(file_in);
        $fclose(file_out);
        $finish;
    end

    // =========================================================
    // 9. WAVEFORM DUMP
    // =========================================================
    initial begin
        $dumpfile("fft_wave.vcd");
        $dumpvars(0, fftmain_tb);
    end

endmodule
