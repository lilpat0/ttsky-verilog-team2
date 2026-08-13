`default_nettype none

module output_controller #(
    parameter int M     = 36,
    parameter int ACC_W = 20,
    parameter int M_W   = 6
)(
    input  logic clk,
    input  logic rst_n,

    input  logic ext_clk,
    input  logic ext_enable,
    input  logic results_ready,

    input  logic signed [M*ACC_W-1:0] result_memory,

    output logic [5:0] output_data
);

    // ============================================================
    // External clock synchronization
    // ============================================================

    logic ext_clk_meta;
    logic ext_clk_sync;
    logic ext_clk_r;

    logic ext_enable_meta;
    logic ext_enable_sync;

    logic ext_clk_pulse;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ext_clk_meta    <= 1'b0;
            ext_clk_sync    <= 1'b0;
            ext_clk_r       <= 1'b0;

            ext_enable_meta <= 1'b0;
            ext_enable_sync <= 1'b0;
        end
        else begin
            ext_clk_meta    <= ext_clk;
            ext_clk_sync    <= ext_clk_meta;
            ext_clk_r       <= ext_clk_sync;

            ext_enable_meta <= ext_enable;
            ext_enable_sync <= ext_enable_meta;
        end
    end

    assign ext_clk_pulse = ext_clk_sync && !ext_clk_r;


    // ============================================================
    // Output indices
    //
    // result_memory[0] is visible immediately when results_ready
    // becomes active.
    //
    // Each output-clock event advances to the NEXT result.
    //
    // Therefore:
    //
    // before pulse #1 : result[0]
    // after  pulse #1 : result[1]
    // after  pulse #2 : result[2]
    // ...
    // after  pulse #35: result[35]
    // ============================================================

    logic [M_W-1:0] internal_index;
    logic [M_W-1:0] external_index;


    // ============================================================
    // Internal clock output index
    //
    // Keep result[0] visible when results_ready first becomes
    // active.
    //
    // The index must NOT advance on the same clock edge that
    // results_ready first becomes active.
    //
    // After that first cycle, each normal clk advances to the
    // next output.
    // ============================================================

    logic internal_results_ready_d;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            internal_index           <= '0;
            internal_results_ready_d <= 1'b0;
        end
        else begin
            internal_results_ready_d <= results_ready;

            if (!results_ready) begin
                internal_index <= '0;
            end
            else if (!internal_results_ready_d) begin
                internal_index <= '0;
            end
            else if (!ext_enable_sync) begin
                if (internal_index < M-1)
                    internal_index <= internal_index + 1'b1;
            end
        end
    end


    // ============================================================
    // External clock output index
    // ============================================================

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            external_index <= '0;
        end
        else if (!results_ready) begin
            external_index <= '0;
        end
        else if (ext_enable_sync && ext_clk_pulse) begin
            if (external_index < M-1)
                external_index <= external_index + 1'b1;
        end
    end


    // ============================================================
    // Select current result
    // ============================================================

    logic signed [ACC_W-1:0] selected_result;

    always_comb begin
        selected_result = '0;

        if (ext_enable_sync) begin
            selected_result =
                result_memory[
                    external_index*ACC_W +: ACC_W
                ];
        end
        else begin
            selected_result =
                result_memory[
                    internal_index*ACC_W +: ACC_W
                ];
        end
    end


    // ============================================================
    // Tiny Tapeout physical output
    //
    // Only six bits are exposed.
    // ============================================================

    always_comb begin
        output_data = selected_result[5:0];
    end

endmodule

`default_nettype wire