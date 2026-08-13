module fsm (
    input  logic clk,
    input  logic rst_n,
    input  logic enable,
    input  logic start,
    input  logic mmm_done,

    output logic busy,
    output logic done,
    output logic run_mm
);

    typedef enum logic [1:0] {
        IDLE,
        LOAD,
        MMM,
        DONE
    } state_t;

    state_t state, next_state;

    // ==========================================
    // State register
    // ==========================================

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= IDLE;
        else if (enable)
            state <= next_state;
    end

    // ==========================================
    // Next-state and outputs
    // ==========================================

    always_comb begin

        // Defaults
        next_state = state;
        busy       = 1'b0;
        done       = 1'b0;
        run_mm     = 1'b0;

        case (state)

            // ----------------------------------
            // IDLE
            // ----------------------------------

            IDLE: begin
                if (start) begin
                    next_state = LOAD;
                    busy       = 1'b1;
                end
            end

            // ----------------------------------
            // LOAD
            // ----------------------------------

            LOAD: begin
                busy       = 1'b1;
                next_state = MMM;
            end

            // ----------------------------------
            // Matrix multiplication
            // ----------------------------------

            MMM: begin
                busy = 1'b1;
                run_mm = 1'b1;

                if (mmm_done) begin
                    next_state = DONE;
                end
            end

            // ----------------------------------
            // DONE
            // ----------------------------------

            DONE: begin
                done = 1'b1;

                // Allow another calculation
                if (start) begin
                    next_state = LOAD;
                    done       = 1'b0;
                    busy       = 1'b1;
                end
            end

            // ----------------------------------
            // Safety
            // ----------------------------------

            default: begin
                next_state = IDLE;
            end

        endcase
    end

endmodule
