
`default_nettype none

module mmm_sequencer #(
    parameter int M   = 36,
    parameter int K   = 9,
    parameter int M_W = 6,
    parameter int K_W = 4
)(
    input  logic             clk,
    input  logic             rst_n,
    input  logic             enable,
    input  logic             run_mm,

    // ==========================================
    // Address outputs
    // ==========================================

    output logic [M_W-1:0]   a_m,
    output logic [K_W-1:0]   a_k,
    output logic [K_W-1:0]   w_addr,

    // ==========================================
    // MAC control
    // ==========================================

    output logic             mac_valid,
    output logic             mac_clear,

    // ==========================================
    // Result information
    // ==========================================

    output logic             out_valid,
    output logic [M_W-1:0]   out_idx,

    // ==========================================
    // Completion
    // ==========================================

    output logic             mmm_done
);

    // ============================================================
    // Main counters
    // ============================================================

    logic [M_W-1:0] m_cnt;
    logic [K_W-1:0] k_cnt;

    logic issuing;

    // ============================================================
    // Counter conditions
    // ============================================================

    logic last_k;
    logic last_m;
    logic first_k;
    logic issue;

    assign last_k  = (k_cnt == K-1);
    assign last_m  = (m_cnt == M-1);
    assign first_k = (k_cnt == 0);

    assign issue = run_mm && issuing;

    // ============================================================
    // Address outputs
    //
    // These select:
    //
    //   A[m][k]
    //   W[k]
    //
    // for:
    //
    //   C[m] = sum(A[m][k] * W[k])
    // ============================================================

    assign a_m    = m_cnt;
    assign a_k    = k_cnt;
    assign w_addr = k_cnt;

    // ============================================================
    // Counter state
    // ============================================================

    always_ff @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            m_cnt   <= '0;
            k_cnt   <= '0;
            issuing <= 1'b1;

        end

        else if (!run_mm) begin

            // Prepare for the next multiplication.

            m_cnt   <= '0;
            k_cnt   <= '0;
            issuing <= 1'b1;

        end

        else if (enable && issuing) begin

            // ------------------------------------------
            // Finished all K values for this output
            // ------------------------------------------

            if (last_k) begin

                k_cnt <= '0;

                // --------------------------------------
                // Finished all M output positions
                // --------------------------------------

                if (last_m) begin

                    issuing <= 1'b0;

                end

                // --------------------------------------
                // Move to next output position
                // --------------------------------------

                else begin

                    m_cnt <= m_cnt + 1'b1;

                end

            end

            // ------------------------------------------
            // Continue through K
            // ------------------------------------------

            else begin

                k_cnt <= k_cnt + 1'b1;

            end

        end

    end

    // ============================================================
    // Pipeline timing
    //
    // At cycle N:
    //
    //     address is issued
    //
    // At cycle N+1:
    //
    //     synchronous memories produce their data
    //     MAC stage 1 captures the operands
    //
    // At cycle N+2:
    //
    //     MAC stage 2 accumulates the product
    //
    // Therefore:
    //
    //     mac_valid = issue delayed by ONE cycle
    //     mac_clear = first_k delayed by ONE cycle
    //
    // Result information needs THREE stages because it must
    // identify the accumulated result after the MAC pipeline.
    // ============================================================

    logic           v_d1;
    logic           c_d1;

    logic           lastk_d1;
    logic           lastk_d2;
    logic           lastk_d3;

    logic [M_W-1:0] m_d1;
    logic [M_W-1:0] m_d2;
    logic [M_W-1:0] m_d3;

    always_ff @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            v_d1 <= 1'b0;
            c_d1 <= 1'b0;

            lastk_d1 <= 1'b0;
            lastk_d2 <= 1'b0;
            lastk_d3 <= 1'b0;

            m_d1 <= '0;
            m_d2 <= '0;
            m_d3 <= '0;

        end

        else if (!run_mm) begin

            v_d1 <= 1'b0;
            c_d1 <= 1'b0;

            lastk_d1 <= 1'b0;
            lastk_d2 <= 1'b0;
            lastk_d3 <= 1'b0;

            m_d1 <= '0;
            m_d2 <= '0;
            m_d3 <= '0;

        end

        else if (enable) begin

            // ====================================================
            // Stage 1
            //
            // Address was issued during this cycle.
            // The synchronous memories will provide their data
            // after this clock edge.
            // ====================================================

            v_d1 <= issue;
            c_d1 <= issue && first_k;

            lastk_d1 <= issue && last_k;
            m_d1     <= m_cnt;

            // ====================================================
            // Stage 2
            //
            // MAC stage 1 captures the memory data here.
            //
            // Result bookkeeping continues through the pipeline.
            // ====================================================

            lastk_d2 <= lastk_d1;
            m_d2     <= m_d1;

            // ====================================================
            // Stage 3
            //
            // MAC stage 2 produces the accumulated result here.
            // ====================================================

            lastk_d3 <= lastk_d2;
            m_d3     <= m_d2;

        end

    end

    // ============================================================
    // MAC control
    //
    // IMPORTANT:
    //
    // Only ONE delay is required from the address issue to the
    // MAC's stage-1 input.
    // ============================================================

    assign mac_valid = v_d1;
    assign mac_clear = c_d1;

    // ============================================================
    // Output result information
    // ============================================================

    assign out_valid = lastk_d3;
    assign out_idx   = m_d3;

    // ============================================================
    // Matrix multiplication complete
    // ============================================================

    assign mmm_done =
        lastk_d3 &&
        (m_d3 == M-1);

endmodule
