`timescale 1ns/1ps
`default_nettype none

module tb_internal;

    // ============================================================
    // Tiny Tapeout interface
    // ============================================================

    logic [7:0] ui_in;
    wire  [7:0] uo_out;

    logic [7:0] uio_in;
    wire  [7:0] uio_out;
    wire  [7:0] uio_oe;

    logic ena;
    logic clk;
    logic rst_n;

    // ============================================================
    // DUT
    // ============================================================

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
    // Tiny Tapeout pin definitions
    // ============================================================

    localparam integer EXT_CLK       = 0;
    localparam integer OUTPUT_ENABLE = 1;
    localparam integer START         = 2;
    localparam integer IMAGE_WE      = 3;
    localparam integer WEIGHT_WE     = 4;

    localparam integer RESULT_BITS = 6;
    localparam integer BUSY_BIT    = 6;
    localparam integer DONE_BIT    = 7;

    // ============================================================
    // CNN dimensions
    // ============================================================

    localparam integer H = 8;
    localparam integer W = 8;

    localparam integer OH = 6;
    localparam integer OW = 6;

    localparam integer NUM_IMAGE  = 64;
    localparam integer NUM_KERNEL = 9;
    localparam integer NUM_OUTPUT = 36;

    // ============================================================
    // Test data
    // ============================================================

    integer image  [0:NUM_IMAGE-1];
    integer kernel [0:NUM_KERNEL-1];

    integer expected [0:NUM_OUTPUT-1];
    integer actual   [0:NUM_OUTPUT-1];

    integer i;
    integer r;
    integer c;
    integer kr;
    integer kc;

    integer sum;
    integer errors;

    // ============================================================
    // Main clock
    // ============================================================

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // ============================================================
    // Integer -> 8-bit representation
    // ============================================================

    function [7:0] to_u8(input integer value);
        begin
            to_u8 = value & 8'hFF;
        end
    endfunction

    // ============================================================
    // Reset DUT
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
    // Write image
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
    // Write weight
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
    // Upload image
    // ============================================================

    task upload_image;
        begin

            $display("Uploading image...");

            for (i = 0; i < NUM_IMAGE; i = i + 1)
                write_image(image[i]);

            $display("Image upload complete.");

        end
    endtask

    // ============================================================
    // Upload kernel
    // ============================================================

    task upload_kernel;
        begin

            $display("Uploading kernel...");

            for (i = 0; i < NUM_KERNEL; i = i + 1)
                write_weight(kernel[i]);

            $display("Kernel upload complete.");

        end
    endtask

    // ============================================================
    // Start CNN
    // ============================================================

    task start_cnn;
        begin

            $display("Starting CNN...");

            uio_in[START] = 1'b1;

            @(posedge clk);

            uio_in[START] = 1'b0;

            @(posedge clk);

        end
    endtask

    // ============================================================
    // Calculate expected convolution
    // ============================================================

    task calculate_expected;
        begin

            for (r = 0; r < OH; r = r + 1) begin

                for (c = 0; c < OW; c = c + 1) begin

                    sum = 0;

                    for (kr = 0; kr < 3; kr = kr + 1) begin

                        for (kc = 0; kc < 3; kc = kc + 1) begin

                            sum =
                                sum +
                                image[(r + kr) * W + (c + kc)] *
                                kernel[kr * 3 + kc];

                        end

                    end

                    expected[r * OW + c] = sum & 6'h3F;

                end

            end

        end
    endtask

    // ============================================================
    // Print expected matrix
    // ============================================================

    task print_expected;
        begin

            $display("");
            $display("EXPECTED OUTPUT:");

            for (r = 0; r < OH; r = r + 1) begin

                $write("  ");

                for (c = 0; c < OW; c = c + 1)
                    $write("%4d", expected[r * OW + c]);

                $display("");

            end

        end
    endtask

    // ============================================================
    // DEBUG DONE / OUTPUT TIMING
    //
    // This is the important diagnostic.
    //
    // We wait for DONE and then examine the output immediately
    // and for several following clocks.
    //
    // No internal DUT signals are accessed.
    // ============================================================

    task debug_done_timing;

        integer timeout;
        integer n;

        begin

            $display("");
            $display("============================================");
            $display("DONE / INTERNAL OUTPUT TIMING DEBUG");
            $display("============================================");

            // Internal clock mode.
            uio_in[OUTPUT_ENABLE] = 1'b0;

            // External clock permanently LOW.
            uio_in[EXT_CLK] = 1'b0;

            timeout = 0;

            $display("");
            $display("Waiting for DONE...");

            // ----------------------------------------------------
            // Wait for DONE.
            // ----------------------------------------------------

            while (uo_out[DONE_BIT] !== 1'b1) begin

                @(posedge clk);

                timeout = timeout + 1;

                if (timeout > 20000) begin

                    $display("");
                    $display("ERROR: DONE timeout.");
                    $finish;

                end

            end

            // ----------------------------------------------------
            // We are now immediately after the clock edge where
            // DONE was detected.
            //
            // Sample before another clock edge occurs.
            // ----------------------------------------------------

            #1;

            $display("");
            $display("DONE detected.");
            $display("");
            $display("Immediately after DONE edge:");
            $display(
                "  DONE   = %b",
                uo_out[DONE_BIT]
            );
            $display(
                "  BUSY   = %b",
                uo_out[BUSY_BIT]
            );
            $display(
                "  OUTPUT = %02d",
                uo_out[RESULT_BITS-1:0]
            );
            $display(
                "  EXPECT = %02d",
                expected[0]
            );

            // ----------------------------------------------------
            // Examine several following internal clock cycles.
            // ----------------------------------------------------

            $display("");
            $display("Following internal clock cycles:");
            $display("");

            for (n = 0; n < 8; n = n + 1) begin

                @(posedge clk);

                #1;

                $display(
                    "  CLK +%0d: DONE=%b BUSY=%b OUTPUT=%02d",
                    n + 1,
                    uo_out[DONE_BIT],
                    uo_out[BUSY_BIT],
                    uo_out[RESULT_BITS-1:0]
                );

            end

            $display("");
            $display("============================================");
            $display("END DONE TIMING DEBUG");
            $display("============================================");
            $display("");

        end

    endtask

    // ============================================================
    // Internal clock output test
    //
    // IMPORTANT:
    //
    // We assume debug_done_timing has already shown the timing.
    //
    // This test reads the output stream from the point at which
    // the DONE timing leaves the output controller.
    // ============================================================

    task test_internal_clock;

        integer j;

        begin

            $display("");
            $display("--------------------------------------------");
            $display("INTERNAL CLOCK OUTPUT TEST");
            $display("--------------------------------------------");
            $display("OUTPUT_ENABLE = 0");
            $display("EXT_CLK       = 0");
            $display("");

            // Ensure internal clock mode.
            uio_in[OUTPUT_ENABLE] = 1'b0;

            // External clock never toggles.
            uio_in[EXT_CLK] = 1'b0;

            // ----------------------------------------------------
            // IMPORTANT:
            //
            // Do NOT wait extra clocks here.
            //
            // The purpose of this test is to show exactly what
            // the internal output path does after DONE.
            // ----------------------------------------------------

            #1;

            actual[0] = uo_out[RESULT_BITS-1:0];

            $display(
                "output[%02d] = %02d    expected = %02d",
                0,
                actual[0],
                expected[0]
            );

            for (j = 1; j < NUM_OUTPUT; j = j + 1) begin

                @(posedge clk);

                #1;

                actual[j] = uo_out[RESULT_BITS-1:0];

                $display(
                    "output[%02d] = %02d    expected = %02d",
                    j,
                    actual[j],
                    expected[j]
                );

            end

        end

    endtask

    // ============================================================
    // Check results
    // ============================================================

    task check_results;
        begin

            errors = 0;

            for (i = 0; i < NUM_OUTPUT; i = i + 1) begin

                if (actual[i] !== expected[i]) begin

                    $display(
                        "MISMATCH [%02d]: got %02d, expected %02d",
                        i,
                        actual[i],
                        expected[i]
                    );

                    errors = errors + 1;

                end

            end

            $display("");
            $display("--------------------------------------------");

            if (errors == 0) begin

                $display("INTERNAL CLOCK: PASS");
                $display("36/36 outputs correct.");

            end
            else begin

                $display("INTERNAL CLOCK: FAIL");
                $display(
                    "%0d/36 outputs incorrect.",
                    errors
                );

            end

            $display("--------------------------------------------");

        end
    endtask

    // ============================================================
    // Print actual matrix
    // ============================================================

    task print_actual;
        begin

            $display("");
            $display("ACTUAL INTERNAL-CLOCK OUTPUT:");

            for (r = 0; r < OH; r = r + 1) begin

                $write("  ");

                for (c = 0; c < OW; c = c + 1)
                    $write("%4d", actual[r * OW + c]);

                $display("");

            end

        end
    endtask

    // ============================================================
    // Test data
    // ============================================================

    task setup_test;
        begin

            image[0]=3;
            image[1]=7;
            image[2]=12;
            image[3]=5;
            image[4]=9;
            image[5]=14;
            image[6]=2;
            image[7]=8;

            image[8]=16;
            image[9]=4;
            image[10]=11;
            image[11]=20;
            image[12]=6;
            image[13]=13;
            image[14]=18;
            image[15]=1;

            image[16]=10;
            image[17]=22;
            image[18]=5;
            image[19]=17;
            image[20]=8;
            image[21]=3;
            image[22]=15;
            image[23]=19;

            image[24]=6;
            image[25]=14;
            image[26]=21;
            image[27]=2;
            image[28]=16;
            image[29]=7;
            image[30]=11;
            image[31]=23;

            image[32]=18;
            image[33]=9;
            image[34]=4;
            image[35]=25;
            image[36]=13;
            image[37]=20;
            image[38]=5;
            image[39]=12;

            image[40]=7;
            image[41]=15;
            image[42]=24;
            image[43]=6;
            image[44]=10;
            image[45]=2;
            image[46]=17;
            image[47]=9;

            image[48]=11;
            image[49]=3;
            image[50]=8;
            image[51]=19;
            image[52]=22;
            image[53]=14;
            image[54]=4;
            image[55]=16;

            image[56]=5;
            image[57]=13;
            image[58]=20;
            image[59]=7;
            image[60]=1;
            image[61]=18;
            image[62]=9;
            image[63]=21;

            kernel[0]=2;
            kernel[1]=-1;
            kernel[2]=3;

            kernel[3]=1;
            kernel[4]=2;
            kernel[5]=-2;

            kernel[6]=3;
            kernel[7]=1;
            kernel[8]=-1;

        end
    endtask

    // ============================================================
    // MAIN
    // ============================================================

    initial begin

        // --------------------------------------------------------
        // Initial state
        // --------------------------------------------------------

        ena    = 1'b0;
        rst_n  = 1'b0;

        ui_in  = 8'h00;
        uio_in = 8'h00;

        // --------------------------------------------------------
        // Header
        // --------------------------------------------------------

        $display("");
        $display("############################################");
        $display("# INTERNAL CLOCK ONLY TEST");
        $display("############################################");

        // --------------------------------------------------------
        // Setup test
        // --------------------------------------------------------

        setup_test();

        calculate_expected();

        print_expected();

        // --------------------------------------------------------
        // Reset
        // --------------------------------------------------------

        reset_dut();

        // --------------------------------------------------------
        // Explicitly select internal output clock mode.
        // --------------------------------------------------------

        uio_in[OUTPUT_ENABLE] = 1'b0;
        uio_in[EXT_CLK]       = 1'b0;

        // --------------------------------------------------------
        // Upload image
        // --------------------------------------------------------

        upload_image();

        // --------------------------------------------------------
        // Upload kernel
        // --------------------------------------------------------

        upload_kernel();

        // --------------------------------------------------------
        // Start CNN
        // --------------------------------------------------------

        start_cnn();

        // --------------------------------------------------------
        // FIRST:
        //
        // Diagnose exactly what happens around DONE.
        // --------------------------------------------------------

        debug_done_timing();

        // --------------------------------------------------------
        // NOTE:
        //
        // debug_done_timing intentionally advances 8 clocks.
        //
        // Therefore the following complete-stream comparison
        // would no longer start at output 0.
        //
        // We do NOT use the results from this debug run as the
        // formal pass/fail test.
        //
        // The debug output above is what we need to inspect to
        // determine the RTL timing.
        // --------------------------------------------------------

        $display("");
        $display("============================================");
        $display("TIMING DEBUG COMPLETE");
        $display("============================================");
        $display("");
        $display("The debug run intentionally advanced the");
        $display("internal output clock.");
        $display("");
        $display("Use the CLK +N values above to determine");
        $display("when output[0] becomes valid.");
        $display("");

        #20;

        $finish;

    end

endmodule

`default_nettype wire