`timescale 1ns/1ps
`default_nettype none

module tb;

    // ============================================================
    // DUT INTERFACE
    // ============================================================

    logic [7:0] ui_in;
    wire  [7:0] uo_out;

    logic [7:0] uio_in;
    wire  [7:0] uio_out;
    wire  [7:0] uio_oe;

    logic ena;
    logic clk;
    logic rst_n;

    tt_um_cnn_accel dut (
        .ui_in   (ui_in),
        .uo_out  (uo_out),
        .uio_in  (uio_in),
        .uio_out (uio_out),
        .uio_oe  (uio_oe),
        .ena     (ena),
        .clk     (clk),
        .rst_n   (rst_n)
    );

    // ============================================================
    // TINY TAPEOUT PIN DEFINITIONS
    // ============================================================

    localparam integer EXT_CLK       = 0;
    localparam integer OUTPUT_ENABLE = 1;
    localparam integer START         = 2;
    localparam integer IMAGE_WE      = 3;
    localparam integer WEIGHT_WE     = 4;

    localparam integer BUSY_BIT = 6;
    localparam integer DONE_BIT = 7;

    // ============================================================
    // CNN PARAMETERS
    // ============================================================

    localparam integer H = 8;
    localparam integer W = 8;

    localparam integer KH = 3;
    localparam integer KW = 3;

    localparam integer OH = 6;
    localparam integer OW = 6;

    localparam integer NUM_IMAGE  = 64;
    localparam integer NUM_KERNEL = 9;
    localparam integer NUM_OUTPUT = 36;

    // ============================================================
    // TEST ARRAYS
    // ============================================================

    integer image [0:NUM_IMAGE-1];
    integer kernel[0:NUM_KERNEL-1];

    integer expected[0:NUM_OUTPUT-1];

    integer actual_internal[0:NUM_OUTPUT-1];
    integer actual_external[0:NUM_OUTPUT-1];

    integer i;
    integer r;
    integer c;
    integer kr;
    integer kc;

    integer sum;

    integer internal_errors;
    integer external_errors;

    // ============================================================
    // MAIN CLOCK
    // ============================================================

    initial begin
        clk = 1'b0;

        forever
            #5 clk = ~clk;
    end

    // ============================================================
    // INTEGER -> 8 BIT VALUE
    // ============================================================

    function [7:0] to_u8(input integer value);

        begin
            to_u8 = value & 8'hFF;
        end

    endfunction

    // ============================================================
    // READ 6-BIT PHYSICAL OUTPUT
    // ============================================================

    function integer read_output;

        begin
            read_output = uo_out[5:0];
        end

    endfunction

    // ============================================================
    // RESET
    // ============================================================

    task reset_dut;

        begin

            ena    = 1'b0;
            rst_n  = 1'b0;

            ui_in  = 8'h00;
            uio_in = 8'h00;

            repeat (5)
                @(posedge clk);

            rst_n = 1'b1;

            repeat (3)
                @(posedge clk);

            ena = 1'b1;

            repeat (2)
                @(posedge clk);

        end

    endtask

    // ============================================================
    // WRITE IMAGE VALUE
    // ============================================================

    task write_image(input integer value);

        begin

            ui_in = to_u8(value);

            uio_in[IMAGE_WE] = 1'b1;

            @(posedge clk);

            uio_in[IMAGE_WE] = 1'b0;

            @(posedge clk);

        end

    endtask

    // ============================================================
    // WRITE KERNEL VALUE
    // ============================================================

    task write_weight(input integer value);

        begin

            ui_in = to_u8(value);

            uio_in[WEIGHT_WE] = 1'b1;

            @(posedge clk);

            uio_in[WEIGHT_WE] = 1'b0;

            @(posedge clk);

        end

    endtask

    // ============================================================
    // UPLOAD IMAGE
    // ============================================================

    task upload_image;

        begin

            $display("");
            $display("--------------------------------------------");
            $display("UPLOADING 8x8 IMAGE");
            $display("--------------------------------------------");

            for (i = 0; i < NUM_IMAGE; i = i + 1)
                write_image(image[i]);

            $display("Image upload complete.");

        end

    endtask

    // ============================================================
    // UPLOAD KERNEL
    // ============================================================

    task upload_kernel;

        begin

            $display("");
            $display("--------------------------------------------");
            $display("UPLOADING 3x3 KERNEL");
            $display("--------------------------------------------");

            for (i = 0; i < NUM_KERNEL; i = i + 1)
                write_weight(kernel[i]);

            $display("Kernel upload complete.");

        end

    endtask

    // ============================================================
    // START CNN
    // ============================================================

    task start_cnn;

        begin

            uio_in[START] = 1'b1;

            @(posedge clk);

            uio_in[START] = 1'b0;

            @(posedge clk);

        end

    endtask

    // ============================================================
    // WAIT FOR BUSY
    // ============================================================

    task wait_for_busy;

        integer timeout;

        begin

            timeout = 0;

            while (uo_out[BUSY_BIT] !== 1'b1) begin

                @(posedge clk);

                timeout = timeout + 1;

                if (timeout > 20000) begin
                    $display("ERROR: BUSY timeout.");
                    $finish;
                end

            end

            $display("BUSY = 1");

        end

    endtask

    // ============================================================
    // WAIT FOR DONE
    // ============================================================

    task wait_for_done;

        integer timeout;

        begin

            timeout = 0;

            while (uo_out[DONE_BIT] !== 1'b1) begin

                @(posedge clk);

                timeout = timeout + 1;

                if (timeout > 20000) begin
                    $display("ERROR: DONE timeout.");
                    $finish;
                end

            end

            $display("DONE = 1");

        end

    endtask

    // ============================================================
    // SOFTWARE REFERENCE
    //
    // The physical output is only 6 bits.
    // Therefore expected values are reduced to bits [5:0].
    // ============================================================

    task calculate_expected;

        begin

            for (r = 0; r < OH; r = r + 1) begin

                for (c = 0; c < OW; c = c + 1) begin

                    sum = 0;

                    for (kr = 0; kr < KH; kr = kr + 1) begin

                        for (kc = 0; kc < KW; kc = kc + 1) begin

                            sum =
                                sum +
                                image[(r + kr) * W + (c + kc)]
                                *
                                kernel[kr * KW + kc];

                        end

                    end

                    expected[r * OW + c] = sum & 6'h3F;

                end

            end

        end

    endtask

    // ============================================================
    // PRINT IMAGE
    // ============================================================

    task print_image;

        begin

            $display("");
            $display("INPUT IMAGE:");

            for (r = 0; r < H; r = r + 1) begin

                $write("  ");

                for (c = 0; c < W; c = c + 1)
                    $write("%6d", image[r * W + c]);

                $display("");

            end

        end

    endtask

    // ============================================================
    // PRINT KERNEL
    // ============================================================

    task print_kernel;

        begin

            $display("");
            $display("KERNEL:");

            for (r = 0; r < KH; r = r + 1) begin

                $write("  ");

                for (c = 0; c < KW; c = c + 1)
                    $write("%6d", kernel[r * KW + c]);

                $display("");

            end

        end

    endtask

    // ============================================================
    // PRINT EXPECTED OUTPUT
    // ============================================================

    task print_expected;

        begin

            $display("");
            $display("EXPECTED 6x6 OUTPUT:");

            for (r = 0; r < OH; r = r + 1) begin

                $write("  Row %0d: ", r);

                for (c = 0; c < OW; c = c + 1)
                    $write("%6d", expected[r * OW + c]);

                $display("");

            end

        end

    endtask

    // ============================================================
    // INTERNAL CLOCK OUTPUT
    //
    // OUTPUT_ENABLE = 0
    //
    // IMPORTANT:
    //
    // When DONE becomes active, internal_index is already 0
    // and result[0] is immediately visible.
    //
    // Therefore DO NOT wait extra clocks before sampling the
    // first output.
    //
    // Each subsequent clk advances to the next result.
    // ============================================================

    task read_internal_clock;

        integer j;

        begin

            $display("");
            $display("--------------------------------------------");
            $display("READING OUTPUT USING INTERNAL CLOCK");
            $display("--------------------------------------------");

            uio_in[OUTPUT_ENABLE] = 1'b0;
            uio_in[EXT_CLK]       = 1'b0;

            // ----------------------------------------------------
            // IMPORTANT FIX:
            //
            // Do NOT use repeat(3) here.
            //
            // result[0] is already visible immediately after DONE.
            // ----------------------------------------------------

            #1;

            actual_internal[0] = read_output();

            // ----------------------------------------------------
            // Every following system clock advances the internal
            // output index by one.
            // ----------------------------------------------------

            for (j = 1; j < NUM_OUTPUT; j = j + 1) begin

                @(posedge clk);

                #1;

                actual_internal[j] = read_output();

            end

            $display("Internal-clock read complete.");

        end

    endtask

    // ============================================================
    // EXTERNAL CLOCK OUTPUT
    //
    // OUTPUT_ENABLE = 1
    //
    // No hierarchical DUT signals are accessed.
    // ============================================================

    task read_external_clock;

        integer j;

        begin

            $display("");
            $display("--------------------------------------------");
            $display("READING OUTPUT USING EXTERNAL CLOCK");
            $display("--------------------------------------------");

            uio_in[OUTPUT_ENABLE] = 1'b1;
            uio_in[EXT_CLK]       = 1'b0;

            repeat (4)
                @(posedge clk);

            // First output.
            #1;

            actual_external[0] = read_output();

            for (j = 1; j < NUM_OUTPUT; j = j + 1) begin

                // Make sure external clock starts LOW.
                uio_in[EXT_CLK] = 1'b0;

                repeat (2)
                    @(posedge clk);

                // Rising edge.
                uio_in[EXT_CLK] = 1'b1;

                repeat (4)
                    @(posedge clk);

                // Return LOW.
                uio_in[EXT_CLK] = 1'b0;

                repeat (2)
                    @(posedge clk);

                #1;

                actual_external[j] = read_output();

            end

            uio_in[EXT_CLK]       = 1'b0;
            uio_in[OUTPUT_ENABLE] = 1'b0;

            repeat (4)
                @(posedge clk);

            $display("External-clock read complete.");

        end

    endtask

    // ============================================================
    // PRINT THREE MATRICES
    // ============================================================

    task print_output_matrices;

        begin

            $display("");
            $display("==============================================================");
            $display("OUTPUT MATRICES");
            $display("==============================================================");

            $display("");
            $display("EXPECTED:");
            $display("");

            for (r = 0; r < OH; r = r + 1) begin

                $write("  ");

                for (c = 0; c < OW; c = c + 1)
                    $write("%6d", expected[r * OW + c]);

                $display("");

            end

            $display("");
            $display("INTERNAL CLOCK:");
            $display("");

            for (r = 0; r < OH; r = r + 1) begin

                $write("  ");

                for (c = 0; c < OW; c = c + 1)
                    $write("%6d", actual_internal[r * OW + c]);

                $display("");

            end

            $display("");
            $display("EXTERNAL CLOCK:");
            $display("");

            for (r = 0; r < OH; r = r + 1) begin

                $write("  ");

                for (c = 0; c < OW; c = c + 1)
                    $write("%6d", actual_external[r * OW + c]);

                $display("");

            end

            $display("");
            $display("SIDE-BY-SIDE:");
            $display("");
            $display("       EXPECTED                         INTERNAL CLK                      EXTERNAL CLK");

            for (r = 0; r < OH; r = r + 1) begin

                $write("Row %0d: ", r);

                for (c = 0; c < OW; c = c + 1)
                    $write("%4d", expected[r * OW + c]);

                $write("       ");

                for (c = 0; c < OW; c = c + 1)
                    $write("%4d", actual_internal[r * OW + c]);

                $write("       ");

                for (c = 0; c < OW; c = c + 1)
                    $write("%4d", actual_external[r * OW + c]);

                $display("");

            end

        end

    endtask

    // ============================================================
    // CHECK INTERNAL
    // ============================================================

    task check_internal;

        begin

            internal_errors = 0;

            for (i = 0; i < NUM_OUTPUT; i = i + 1) begin

                if (actual_internal[i] !== expected[i])
                    internal_errors = internal_errors + 1;

            end

            if (internal_errors == 0) begin

                $display("");
                $display("INTERNAL CLOCK: PASS - 36/36");

            end
            else begin

                $display("");
                $display(
                    "INTERNAL CLOCK: FAIL - %0d/36 incorrect",
                    internal_errors
                );

            end

        end

    endtask

    // ============================================================
    // CHECK EXTERNAL
    // ============================================================

    task check_external;

        begin

            external_errors = 0;

            for (i = 0; i < NUM_OUTPUT; i = i + 1) begin

                if (actual_external[i] !== expected[i])
                    external_errors = external_errors + 1;

            end

            if (external_errors == 0) begin

                $display("");
                $display("EXTERNAL CLOCK: PASS - 36/36");

            end
            else begin

                $display("");
                $display(
                    "EXTERNAL CLOCK: FAIL - %0d/36 incorrect",
                    external_errors
                );

            end

        end

    endtask

    // ============================================================
    // RUN TEST
    // ============================================================

    task run_test;

        begin

            reset_dut();

            upload_image();

            upload_kernel();

            calculate_expected();

            start_cnn();

            wait_for_busy();

            wait_for_done();

            read_internal_clock();

            read_external_clock();

            print_output_matrices();

            check_internal();

            check_external();

        end

    endtask

    // ============================================================
    // TEST 1
    //
    // Mixed image / signed kernel.
    // ============================================================

    task setup_mixed_test;

        begin

            image[0]  = 3;
            image[1]  = 7;
            image[2]  = 12;
            image[3]  = 5;
            image[4]  = 9;
            image[5]  = 14;
            image[6]  = 2;
            image[7]  = 8;

            image[8]  = 16;
            image[9]  = 4;
            image[10] = 11;
            image[11] = 20;
            image[12] = 6;
            image[13] = 13;
            image[14] = 18;
            image[15] = 1;

            image[16] = 10;
            image[17] = 22;
            image[18] = 5;
            image[19] = 17;
            image[20] = 8;
            image[21] = 3;
            image[22] = 15;
            image[23] = 19;

            image[24] = 6;
            image[25] = 14;
            image[26] = 21;
            image[27] = 2;
            image[28] = 16;
            image[29] = 7;
            image[30] = 11;
            image[31] = 23;

            image[32] = 18;
            image[33] = 9;
            image[34] = 4;
            image[35] = 25;
            image[36] = 13;
            image[37] = 20;
            image[38] = 5;
            image[39] = 12;

            image[40] = 7;
            image[41] = 15;
            image[42] = 24;
            image[43] = 6;
            image[44] = 10;
            image[45] = 2;
            image[46] = 17;
            image[47] = 9;

            image[48] = 11;
            image[49] = 3;
            image[50] = 8;
            image[51] = 19;
            image[52] = 22;
            image[53] = 14;
            image[54] = 4;
            image[55] = 16;

            image[56] = 5;
            image[57] = 13;
            image[58] = 20;
            image[59] = 7;
            image[60] = 1;
            image[61] = 18;
            image[62] = 9;
            image[63] = 21;

            kernel[0] = 2;
            kernel[1] = -1;
            kernel[2] = 3;

            kernel[3] = 1;
            kernel[4] = 2;
            kernel[5] = -2;

            kernel[6] = 3;
            kernel[7] = 1;
            kernel[8] = -1;

        end

    endtask

    // ============================================================
    // TEST 2: +127 / +127
    // ============================================================

    task setup_positive_extreme;

        begin

            for (i = 0; i < NUM_IMAGE; i = i + 1)
                image[i] = 127;

            for (i = 0; i < NUM_KERNEL; i = i + 1)
                kernel[i] = 127;

        end

    endtask

    // ============================================================
    // TEST 3: -128 / +127
    // ============================================================

    task setup_negative_extreme;

        begin

            for (i = 0; i < NUM_IMAGE; i = i + 1)
                image[i] = -128;

            for (i = 0; i < NUM_KERNEL; i = i + 1)
                kernel[i] = 127;

        end

    endtask

    // ============================================================
    // TEST 4: -128 / -128
    // ============================================================

    task setup_min_min;

        begin

            for (i = 0; i < NUM_IMAGE; i = i + 1)
                image[i] = -128;

            for (i = 0; i < NUM_KERNEL; i = i + 1)
                kernel[i] = -128;

        end

    endtask

    // ============================================================
    // MAIN
    // ============================================================

    initial begin

        ena    = 1'b0;
        rst_n  = 1'b0;
        ui_in  = 8'h00;
        uio_in = 8'h00;

        // ========================================================
        // TEST 1
        // ========================================================

        $display("");
        $display("############################################");
        $display("# TEST 1: MIXED SIGNED DATA");
        $display("############################################");

        setup_mixed_test();

        print_image();
        print_kernel();

        calculate_expected();
        print_expected();

        run_test();

        // ========================================================
        // TEST 2
        // ========================================================

        $display("");
        $display("############################################");
        $display("# TEST 2: +127 / +127");
        $display("############################################");

        setup_positive_extreme();

        print_image();
        print_kernel();

        calculate_expected();
        print_expected();

        run_test();

        // ========================================================
        // TEST 3
        // ========================================================

        $display("");
        $display("############################################");
        $display("# TEST 3: -128 / +127");
        $display("############################################");

        setup_negative_extreme();

        print_image();
        print_kernel();

        calculate_expected();
        print_expected();

        run_test();

        // ========================================================
        // TEST 4
        // ========================================================

        $display("");
        $display("############################################");
        $display("# TEST 4: -128 / -128");
        $display("############################################");

        setup_min_min();

        print_image();
        print_kernel();

        calculate_expected();
        print_expected();

        run_test();

        // ========================================================
        // COMPLETE
        // ========================================================

        $display("");
        $display("============================================");
        $display("      CNN ACCELERATOR TEST COMPLETE");
        $display("============================================");
        $display("");
        $display("Verified through Tiny Tapeout pins:");
        $display("");
        $display("  ui_in[7:0]    = image / weight data");
        $display("  uio_in[0]     = external clock");
        $display("  uio_in[1]     = output enable");
        $display("  uio_in[2]     = start");
        $display("  uio_in[3]     = image write enable");
        $display("  uio_in[4]     = weight write enable");
        $display("  uo_out[5:0]   = result");
        $display("  uo_out[6]     = busy");
        $display("  uo_out[7]     = done");
        $display("");
        $display("No hierarchical/internal DUT signals were accessed.");
        $display("");

        #100;

        $finish;

    end

endmodule

`default_nettype wire