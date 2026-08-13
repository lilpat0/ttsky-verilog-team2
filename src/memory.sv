//=====================================================================
// memory -- simple single-port register-array memory with proper read/write handling
//
//   DEPTH is now explicit rather than implied by 2**ADDR_WIDTH. The
//   weight memory holds K = 9 taps and the output feature map holds
//   M = 36 entries; rounding both up to a power of two wasted 280
//   flip-flops between them. 
//
//   Read and write are properly sequenced:
//   - Only one operation per cycle (write takes priority)
//   - Read output updates only when we is low
//   - Data is stable and synchronized
//=====================================================================
module memory #(
    parameter int DATA_WIDTH = 8,
    parameter int ADDR_WIDTH = 4,
    parameter int DEPTH      = (1 << ADDR_WIDTH)
) (
    input  logic                  clk,
    input  logic                  rst_n,
    input  logic                  we,
    input  logic [ADDR_WIDTH-1:0] addr,
    input  logic [DATA_WIDTH-1:0] din,
    output logic [DATA_WIDTH-1:0] dout
);

    logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    // ========================================================
    // Synchronous read and write
    //
    // Write takes priority: if we=1, write to memory and
    // do NOT update dout (avoid reading back written data
    // in same cycle, which could cause timing issues).
    // 
    // If we=0, perform synchronous read.
    // ========================================================

    always_ff @(posedge clk) begin
        if (we) begin
            // Write cycle: store data
            if (addr < DEPTH)
                mem[addr] <= din;
            // dout is not updated during write to maintain read/write separation
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dout <= '0;
        end
        else if (!we) begin
            // Read cycle: fetch data
            if (addr < DEPTH)
                dout <= mem[addr];
            else
                dout <= '0;  // Out-of-bounds read returns zero
        end
        // When we=1, dout retains previous value (no change)
    end

endmodule
