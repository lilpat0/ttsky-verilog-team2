`default_nettype none

module cnn_accelerator #(
    parameter int DATA_W = 8,
    parameter int ACC_W  = 20,
    parameter int IF_AW  = 6,
    parameter int M_W    = 6,
    parameter int K_W    = 4,
    parameter int M      = 36,
    parameter int K      = 9
)(
    input  logic clk,
    input  logic rst_n,
    input  logic ena,

    // ========================================================
    // 8-bit image / weight input
    // ========================================================

    input  logic [DATA_W-1:0] input_data,

    // ========================================================
    // CNN control
    // ========================================================

    input  logic start,
    input  logic image_write_enable,
    input  logic weight_write_enable,

    // ========================================================
    // Output-clock interface
    // ========================================================

    input  logic ext_clk,
    input  logic ext_output_enable,

    // ========================================================
    // 6-bit physical output
    // ========================================================

    output logic [5:0] output_data,

    output logic busy,
    output logic done
);

    // ========================================================
    // CNN CONTROL
    // ========================================================

    logic run_mm;
    logic mmm_done;

    logic start_d;
    logic start_pulse;
    logic accepted_start;


    // ========================================================
    // MATRIX MULTIPLY SEQUENCER
    // ========================================================

    logic [M_W-1:0] matrix_row;
    logic [K_W-1:0] matrix_column;
    logic [K_W-1:0] weight_address;

    logic mac_valid;
    logic mac_clear;

    logic sequencer_output_valid;
    logic [M_W-1:0] sequencer_output_index;


    // ========================================================
    // MEMORY LOADING
    // ========================================================

    logic [IF_AW-1:0] image_address;
    logic [K_W-1:0]   weight_load_address;

    logic image_full;
    logic weight_full;

    logic image_loaded;
    logic weight_loaded;

    logic image_write;
    logic weight_write;


    // ========================================================
    // AUTO START
    // ========================================================

    logic loaded_both;
    logic loaded_both_d;
    logic auto_start_pulse;


    // ========================================================
    // DATAPATH
    // ========================================================

    logic signed [DATA_W-1:0] image_data;
    logic signed [DATA_W-1:0] weight_data;

    logic signed [ACC_W-1:0] accumulator_output;


    // ========================================================
    // RESULT MEMORY
    //
    // One result for each of the 36 output positions.
    // ========================================================

    logic signed [ACC_W-1:0] result_memory [0:M-1];


    // ========================================================
    // START EDGE DETECTOR
    // ========================================================

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            start_d <= 1'b0;
        else
            start_d <= start;
    end

    assign start_pulse = start && !start_d;


    // ========================================================
    // AUTO-START EDGE DETECTOR
    // ========================================================

    assign loaded_both = image_loaded && weight_loaded;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            loaded_both_d <= 1'b0;
        else if (ena)
            loaded_both_d <= loaded_both;
    end

    assign auto_start_pulse =
        ena &&
        loaded_both &&
        !loaded_both_d;


    // ========================================================
    // ACCEPTED START
    // ========================================================

    assign accepted_start =
        ena &&
        (start_pulse || auto_start_pulse) &&
        image_loaded &&
        weight_loaded;


    // ========================================================
    // MEMORY WRITE ENABLES
    //
    // Do not allow memory writes while the CNN is running.
    // ========================================================

    assign image_write =
        ena &&
        image_write_enable &&
        !weight_write_enable &&
        !busy &&
        !image_full;

    assign weight_write =
        ena &&
        weight_write_enable &&
        !image_write_enable &&
        !busy &&
        !weight_full;


    // ========================================================
    // IMAGE WRITE ADDRESS / STATUS
    // ========================================================

    always_ff @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin
            image_address <= '0;
            image_full    <= 1'b0;
            image_loaded  <= 1'b0;
        end

        else if (ena) begin

            // A new accepted run begins a new dataset.
            if (accepted_start) begin
                image_address <= '0;
                image_full    <= 1'b0;
                image_loaded  <= 1'b0;
            end

            else if (image_write) begin

                if (image_address == 63) begin
                    image_full   <= 1'b1;
                    image_loaded <= 1'b1;
                end

                else begin
                    image_address <= image_address + 1'b1;

                    // During a new upload, don't claim the image
                    // is complete until the final element arrives.
                    if (image_address == 0)
                        image_loaded <= 1'b0;
                end

            end
        end
    end


    // ========================================================
    // WEIGHT WRITE ADDRESS / STATUS
    // ========================================================

    always_ff @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin
            weight_load_address <= '0;
            weight_full         <= 1'b0;
            weight_loaded       <= 1'b0;
        end

        else if (ena) begin

            // A new accepted run begins a new dataset.
            if (accepted_start) begin
                weight_load_address <= '0;
                weight_full         <= 1'b0;
                weight_loaded       <= 1'b0;
            end

            else if (weight_write) begin

                if (weight_load_address == K-1) begin
                    weight_full   <= 1'b1;
                    weight_loaded <= 1'b1;
                end

                else begin
                    weight_load_address <=
                        weight_load_address + 1'b1;

                    if (weight_load_address == 0)
                        weight_loaded <= 1'b0;
                end

            end
        end
    end


    // ========================================================
    // RESULT MEMORY
    //
    // Clear all old results when a new CNN run starts.
    //
    // This prevents stale results from a previous dataset from
    // surviving into a new calculation.
    // ========================================================

    integer result_clear_i;

    always_ff @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            for (result_clear_i = 0;
                 result_clear_i < M;
                 result_clear_i = result_clear_i + 1) begin

                result_memory[result_clear_i] <= '0;

            end

        end

        else if (ena) begin

            if (accepted_start) begin

                for (result_clear_i = 0;
                     result_clear_i < M;
                     result_clear_i = result_clear_i + 1) begin

                    result_memory[result_clear_i] <= '0;

                end
            end

            else if (sequencer_output_valid) begin

                result_memory[sequencer_output_index]
                    <= accumulator_output;

            end
        end
    end


    // ========================================================
    // FSM
    //
    // The FSM only uses the internal accelerator clock.
    // ext_clk is strictly an output-reading clock.
    // ========================================================

    fsm u_fsm (
        .clk      (clk),
        .rst_n    (rst_n),
        .enable   (ena),
        .start    (accepted_start),
        .mmm_done (mmm_done),

        .busy     (busy),
        .done     (done),
        .run_mm   (run_mm)
    );


    // ========================================================
    // MATRIX MULTIPLY SEQUENCER
    // ========================================================

    mmm_sequencer #(
        .M   (M),
        .K   (K),
        .M_W (M_W),
        .K_W (K_W)
    ) u_sequencer (

        .clk       (clk),
        .rst_n     (rst_n),
        .enable    (ena),

        .run_mm    (run_mm),

        .a_m       (matrix_row),
        .a_k       (matrix_column),
        .w_addr    (weight_address),

        .mac_valid (mac_valid),
        .mac_clear (mac_clear),

        .out_valid (sequencer_output_valid),
        .out_idx   (sequencer_output_index),

        .mmm_done  (mmm_done)
    );


    // ========================================================
    // IM2COL IMAGE PROVIDER
    // ========================================================

    a_provider_im2col #(
        .H      (8),
        .W      (8),
        .M      (M),
        .K      (K),
        .DATA_W (DATA_W),
        .IF_AW  (IF_AW),
        .M_W    (M_W),
        .K_W    (K_W)
    ) u_image_provider (

        .clk       (clk),
        .rst_n     (rst_n),

        .a_m       (matrix_row),
        .a_k       (matrix_column),

        .a_data    (image_data),

        .load_we   (image_write),
        .load_addr (image_address),
        .load_data (input_data)
    );


    // ========================================================
    // WEIGHT MEMORY
    // ========================================================

    memory #(
        .DATA_WIDTH (DATA_W),
        .ADDR_WIDTH (K_W),
        .DEPTH      (K)
    ) u_weight_memory (

        .clk   (clk),
        .rst_n (rst_n),

        .we    (weight_write),

        .addr  (
            weight_write
                ? weight_load_address
                : weight_address
        ),

        .din   (input_data),
        .dout  (weight_data)
    );


    // ========================================================
    // MAC
    // ========================================================

    mac_unit #(
        .DW    (DATA_W),
        .ACC_W (ACC_W)
    ) u_mac (

        .clk       (clk),
        .rst_n     (rst_n),
        .enable    (ena),

        .a         (image_data),
        .b         (weight_data),

        .valid_in  (mac_valid),
        .clear_acc (mac_clear),

        .acc_out   (accumulator_output),

        .valid_out ()
    );


    // ========================================================
    // FLATTEN RESULT MEMORY
    //
    // output_controller expects one large packed vector.
    // ========================================================

    logic signed [M*ACC_W-1:0] result_memory_flat;

    genvar i;

    generate

        for (i = 0; i < M; i = i + 1) begin : result_flatten

            assign result_memory_flat[
                i*ACC_W +: ACC_W
            ] = result_memory[i];

        end

    endgenerate


    // ========================================================
    // OUTPUT CONTROLLER
    // ========================================================

    output_controller #(
        .M     (M),
        .ACC_W (ACC_W),
        .M_W   (M_W)
    ) u_output_controller (

        .clk           (clk),
        .rst_n         (rst_n),

        .ext_clk       (ext_clk),
        .ext_enable    (ext_output_enable),

        .results_ready (done),

        .result_memory (result_memory_flat),

        .output_data   (output_data)
    );

endmodule

`default_nettype wire