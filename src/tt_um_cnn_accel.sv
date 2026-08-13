`default_nettype none

module tt_um_cnn_accel (
    input  logic [7:0] ui_in,
    output logic [7:0] uo_out,
    input  logic [7:0] uio_in,
    output logic [7:0] uio_out,
    output logic [7:0] uio_oe,
    input  logic ena,
    input  logic clk,
    input  logic rst_n
);

    // ========================================================
    // Bidirectional pins
    //
    // We only READ these pins.
    // The chip never drives them.
    //
    // uio[0] = external output clock
    // uio[1] = external output enable
    // ========================================================

    assign uio_oe  = 8'b00000000;
    assign uio_out = 8'b00000000;

    // ========================================================
    // CNN accelerator status, brought out to uo_out[7:6]
    // ========================================================

    logic cnn_busy;
    logic cnn_done;

    // ========================================================
    // CNN accelerator
    // ========================================================

    cnn_accelerator u_cnn (
        .clk                 (clk),
        .rst_n               (rst_n),
        .ena                 (ena),

        // 8-bit image / weight input
        .input_data          (ui_in),

        // Control
        .start               (uio_in[2]),
        .image_write_enable  (uio_in[3]),
        .weight_write_enable (uio_in[4]),

        // External output clock interface
        .ext_clk             (uio_in[0]),
        .ext_output_enable   (uio_in[1]),

        // 6-bit output data
        .output_data         (uo_out[5:0]),

        .busy                (cnn_busy),
        .done                (cnn_done)
    );

    // uo_out[6] = busy, uo_out[7] = done
    assign uo_out[6] = cnn_busy;
    assign uo_out[7] = cnn_done;

endmodule
