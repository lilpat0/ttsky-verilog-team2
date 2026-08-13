`default_nettype none

module mac_unit #(
    parameter int DW    = 8,
    parameter int ACC_W = 20
)(
    input  logic                    clk,
    input  logic                    rst_n,
    input  logic                    enable,

    input  logic signed [DW-1:0]    a,
    input  logic signed [DW-1:0]    b,

    input  logic                    valid_in,
    input  logic                    clear_acc,

    output logic signed [ACC_W-1:0] acc_out,
    output logic                    valid_out
);

    // ============================================================
    // Product
    // ============================================================

    logic signed [(2*DW)-1:0] mult_res;

    // ============================================================
    // Pipeline stage 1
    // ============================================================

    logic signed [(2*DW)-1:0] product_stage1;
    logic                     valid_stage1;
    logic                     clear_stage1;

    // ============================================================
    // Extended accumulator
    //
    // ACC_W = 20
    // Extended accumulator = 21 bits
    //
    // ============================================================

    logic signed [ACC_W:0] acc_extended;
    logic signed [ACC_W:0] product_extended;
    logic signed [ACC_W:0] acc_next;

    // ============================================================
    // Multiply
    // ============================================================

    assign mult_res = a * b;

    // ============================================================
    // Sign extend product to ACC_W+1 bits
    // ============================================================

    always_comb begin

        product_extended = '0;

        product_extended =
            {{(ACC_W + 1 - 2*DW){product_stage1[(2*DW)-1]}},
             product_stage1};

    end

    // ============================================================
    // Stage 1
    //
    // Register multiplication result and control signals.
    // ============================================================

    always_ff @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            product_stage1 <= '0;
            valid_stage1   <= 1'b0;
            clear_stage1   <= 1'b0;

        end

        else if (enable) begin

            product_stage1 <= mult_res;
            valid_stage1   <= valid_in;
            clear_stage1   <= clear_acc;

        end

    end

    // ============================================================
    // Stage 2
    //
    // Accumulate with signed overflow/underflow detection.
    // ============================================================

    always_ff @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            acc_out      <= '0;
            acc_extended <= '0;
            valid_out    <= 1'b0;

        end

        else if (enable) begin

            // ----------------------------------------------------
            // Start a new accumulation
            // ----------------------------------------------------

            if (clear_stage1) begin

                acc_extended <= product_extended;
                acc_out      <= product_extended[ACC_W-1:0];
                valid_out    <= valid_stage1;

            end

            // ----------------------------------------------------
            // Add next MAC product
            // ----------------------------------------------------

            else if (valid_stage1) begin

                acc_next = acc_extended + product_extended;

                // ------------------------------------------------
                // Positive overflow
                //
                // A signed ACC_W result is valid only when the
                // extended sign bit matches the ACC_W sign bit.
                // ------------------------------------------------

                if (
                    acc_next[ACC_W] == 1'b0 &&
                    acc_next[ACC_W-1] == 1'b1
                ) begin

                    acc_extended <= {
                        1'b0,
                        1'b0,
                        {(ACC_W-1){1'b1}}
                    };

                    acc_out <= {
                        1'b0,
                        {(ACC_W-1){1'b1}}
                    };

                end

                // ------------------------------------------------
                // Negative underflow
                // ------------------------------------------------

                else if (
                    acc_next[ACC_W] == 1'b1 &&
                    acc_next[ACC_W-1] == 1'b0
                ) begin

                    acc_extended <= {
                        1'b1,
                        1'b1,
                        {(ACC_W-1){1'b0}}
                    };

                    acc_out <= {
                        1'b1,
                        {(ACC_W-1){1'b0}}
                    };

                end

                // ------------------------------------------------
                // Normal accumulation
                // ------------------------------------------------

                else begin

                    acc_extended <= acc_next;
                    acc_out      <= acc_next[ACC_W-1:0];

                end

                valid_out <= 1'b1;

            end

            // ----------------------------------------------------
            // No valid MAC this cycle
            // ----------------------------------------------------

            else begin

                valid_out <= 1'b0;

            end

        end

    end

endmodule

`default_nettype wire