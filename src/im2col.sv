
`default_nettype none

module a_provider_im2col #(
    parameter int H      = 8,
    parameter int W      = 8,
    parameter int M      = 36,
    parameter int K      = 9,
    parameter int DATA_W = 8,
    parameter int IF_AW  = 6,
    parameter int M_W    = 6,
    parameter int K_W    = 4
)(
    input  logic clk,
    input  logic rst_n,

    // ==========================================
    // IM2COL indices
    // ==========================================

    input  logic [M_W-1:0] a_m,
    input  logic [K_W-1:0] a_k,

    output logic signed [DATA_W-1:0] a_data,

    // ==========================================
    // Image loading interface
    // ==========================================

    input  logic load_we,
    input  logic [IF_AW-1:0] load_addr,
    input  logic signed [DATA_W-1:0] load_data
);

    // ==========================================
    // Address calculation signals
    // ==========================================

    logic [2:0] mr;
    logic [2:0] mc;

    logic [1:0] kr;
    logic [1:0] kc;

    logic [3:0] row;
    logic [3:0] col;

    logic [IF_AW-1:0] ifmap_addr;

    logic a_valid;

    // ==========================================
    // Image memory with input validation
    //
    // 8 x 8 = 64 pixels
    //
    // Input data is stored as-is (signed 8-bit).
    // Load address is bounds-checked to prevent
    // out-of-range writes.
    // ==========================================

    logic signed [DATA_W-1:0] ifmap_mem [0:H*W-1];

    // Write with bounds checking: only write if address is valid
    always_ff @(posedge clk) begin
        if (load_we && (load_addr < H*W)) begin
            // Valid write address: store signed input data
            ifmap_mem[load_addr] <= load_data;
        end
        // Invalid addresses are silently ignored to prevent corruption
    end

    // ==========================================
    // IM2COL address generation
    //
    // M = 36 output positions
    // K = 9 values per 3x3 window
    //
    // a_m:
    //
    //   0  1  2  3  4  5
    //   6  7  8  9 10 11
    //   ...
    //
    // a_k:
    //
    //   0 1 2
    //   3 4 5
    //   6 7 8
    // ==========================================

    always_comb begin

        // Defaults
        mr         = 3'd0;
        mc         = 3'd0;

        kr         = 2'd0;
        kc         = 2'd0;

        row        = 4'd0;
        col        = 4'd0;

        ifmap_addr = '0;
        a_valid    = 1'b0;

        // Make sure indices are inside valid range
        if ((a_m < M) && (a_k < K)) begin

            // ----------------------------------
            // Output window position
            // ----------------------------------

            mr = a_m / 6;
            mc = a_m % 6;

            // ----------------------------------
            // 3x3 kernel position
            // ----------------------------------

            kr = a_k / 3;
            kc = a_k % 3;

            // ----------------------------------
            // Pixel position in original image
            // ----------------------------------

            row = mr + kr;
            col = mc + kc;

            // ----------------------------------
            // Bounds check: ensure row/col are within 8x8 image
            // For 8x8 image with 3x3 kernel:
            //   - mr ranges 0-5 (6 output positions vertically)
            //   - kr ranges 0-2 (3 kernel rows)
            //   - row ranges 0-7 (valid for 8x8 image)
            //   Same logic applies to mc/kc/col
            // ----------------------------------

            if ((row < H) && (col < W)) begin
                // ----------------------------------
                // Convert row/column to memory address
                //
                // address = row * 8 + col
                // ----------------------------------

                ifmap_addr = (row * 8) + col;
                a_valid = 1'b1;
            end
            // else: invalid address - a_valid stays 0
        end
    end

    // ==========================================
    // Synchronous read from image memory
    //
    // Read is synchronous: a_m / a_k determine address,
    // data appears on a_data after one clock cycle.
    // ==========================================

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            a_data <= '0;
        else begin
            if (a_valid) begin
                a_data <= ifmap_mem[ifmap_addr];
            end
            else begin
                a_data <= '0;
            end
        end
    end

endmodule
