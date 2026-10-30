
`timescale 1ns / 1ps

// ============================================================================
// Project   : Simple Parameterized Synchronous FIFO
// File      : sync_fifo.v
// Developer : Ghulam Yaseen Nangraj
// Date      : 2026-10-30
// Platform  : Xilinx Vivado 2025.2.1
// Language  : Verilog-2001
// Purpose   : Store and retrieve data in First-In, First-Out (FIFO) order.
// Notes     : Uses one common clock and a synchronous, active-high reset.
//             No procedural loops are used.
// ============================================================================


// ============================================================================
// MODULE: PARAMETERIZED SYNCHRONOUS FIFO
// ============================================================================
// Function:
//   Stores incoming data in memory and returns stored data in FIFO order.
//   The oldest accepted entry is read first.
//
// Parameters:
//   DATA_WIDTH  : Number of bits in each stored data word.
//   DEPTH       : Number of entries in the FIFO memory.
//   COUNT_WIDTH : Number of bits used by the occupancy counter.
//
// Interface behavior:
//   wr_en   : Requests a write operation.
//   rd_en   : Requests a read operation.
//   data_in : Data to store when a write is accepted.
//   data_out: Registered data from an accepted read.
//   full    : Indicates that the FIFO has reached its configured capacity.
//   empty   : Indicates that the FIFO contains no stored entries.
//   count   : Number of stored entries, from zero through DEPTH.
//
// Reset:
//   rst is synchronous and active-high. State registers are reset on the
//   rising edge of clk when rst is asserted.
// ============================================================================

module sync_fifo #(
    parameter DATA_WIDTH = 8,  // Width of each FIFO data word.
    parameter DEPTH      = 8, // Number of storage locations.

    // ------------------------------------------------------------------------
    // Calculate the occupancy-counter width.
    // ------------------------------------------------------------------------
    // The counter must represent every value from 0 through DEPTH, inclusive.
    //
    // For example, DEPTH = 16 requires 5 bits because a 4-bit unsigned
    // counter can represent only 0 through 15.
    //
    // The nested conditional operators select a suitable width for the
    // supported DEPTH range. No procedural loop is required.
    parameter COUNT_WIDTH =
        (DEPTH <= 2)      ? 2  :
        (DEPTH <= 4)      ? 3  :
        (DEPTH <= 8)      ? 4  :
        (DEPTH <= 16)     ? 5  :
        (DEPTH <= 32)     ? 6  :
        (DEPTH <= 64)     ? 7  :
        (DEPTH <= 128)    ? 8  :
        (DEPTH <= 256)    ? 9  :
        (DEPTH <= 512)    ? 10 :
        (DEPTH <= 1024)   ? 11 :
        (DEPTH <= 2048)   ? 12 :
        (DEPTH <= 4096)   ? 13 :
        (DEPTH <= 8192)   ? 14 :
        (DEPTH <= 16384)  ? 15 :
        (DEPTH <= 32768)  ? 16 :
        (DEPTH <= 65536)  ? 17 : 18
)(
    input  wire                   clk,       // Common FIFO clock.
    input  wire                   rst,       // Synchronous active-high reset.
    input  wire                   wr_en,     // External write request.
    input  wire [DATA_WIDTH-1:0]  data_in,   // Input data word.
    input  wire                   rd_en,     // External read request.

    output reg  [DATA_WIDTH-1:0]  data_out,  // Registered read-data output.
    output wire                  full,      // FIFO full status.
    output wire                  empty,     // FIFO empty status.
    output reg  [COUNT_WIDTH-1:0] count      // Current FIFO occupancy.
);


// ============================================================================
// SECTION 1: CALCULATE THE MEMORY ADDRESS WIDTH
// ============================================================================
// ADDR_WIDTH determines the number of bits in each read/write pointer.
//
// For a power-of-two depth:
//   DEPTH = 16  -> ADDR_WIDTH = 4
//   DEPTH = 32  -> ADDR_WIDTH = 5
//
// This nested conditional expression supports DEPTH values from 1 through
// 65536, as described by the original parameter selection.
//
// For non-power-of-two depths, the selected width is sufficient to represent
// the highest valid address, and the explicit pointer-wrap conditions below
// prevent normal pointer operation from entering an unused address.
localparam ADDR_WIDTH =
    (DEPTH <= 2)      ? 1  :
    (DEPTH <= 4)      ? 2  :
    (DEPTH <= 8)      ? 3  :
    (DEPTH <= 16)     ? 4  :
    (DEPTH <= 32)     ? 5  :
    (DEPTH <= 64)     ? 6  :
    (DEPTH <= 128)    ? 7  :
    (DEPTH <= 256)    ? 8  :
    (DEPTH <= 512)    ? 9  :
    (DEPTH <= 1024)   ? 10 :
    (DEPTH <= 2048)   ? 11 :
    (DEPTH <= 4096)   ? 12 :
    (DEPTH <= 8192)   ? 13 :
    (DEPTH <= 16384)  ? 14 :
    (DEPTH <= 32768)  ? 15 :
    (DEPTH <= 65536)  ? 16 : 17;


// The following commented declaration is an alternative width calculation
// for a power-of-two FIFO depth, but it is not used by this implementation.
//
//localparam COUNT_WIDTH = ADDR_WIDTH + 1;


// ============================================================================
// SECTION 2: FIFO MEMORY AND POINTERS
// ============================================================================

// Declare the FIFO storage array.
//
// Array dimensions:
//   [0:DEPTH-1]      : Valid memory entry indices.
//   [DATA_WIDTH-1:0] : Number of bits in each entry.
//
// Example with DATA_WIDTH = 8 and DEPTH = 16:
//   The FIFO contains 16 entries, each 8 bits wide.
reg [DATA_WIDTH-1:0] memory [0:DEPTH-1];


// Write pointer:
//   Selects the memory location where the next accepted write is stored.
reg [ADDR_WIDTH-1:0] wr_ptr;

// Read pointer:
//   Selects the memory location containing the oldest entry to be read.
reg [ADDR_WIDTH-1:0] rd_ptr;


// ============================================================================
// SECTION 3: FULL AND EMPTY FLAGS
// ============================================================================

// The FIFO is empty when the occupancy counter equals zero.
// No stored entries are available for reading.
assign empty = (count == 0);

// The FIFO is full when the occupancy counter equals DEPTH.
// No additional write can be accepted until space becomes available.
assign full = (count == DEPTH);


// ============================================================================
// SECTION 4: WRITE AND READ ACCEPTANCE
// ============================================================================

// Internal acceptance signals determine whether each request can proceed.
//
// A write is accepted only when:
//   wr_en = 1 : A write is requested.
//   full  = 0 : The FIFO has available storage.
wire wr_accept;
assign wr_accept = wr_en && !full;


// A read is accepted only when:
//   rd_en = 1 : A read is requested.
//   empty = 0 : At least one entry is stored.
wire rd_accept;
assign rd_accept = rd_en && !empty;


// These acceptance signals are also used by the occupancy counter so that
// the count changes only when an operation is actually accepted.


// ============================================================================
// SECTION 5: WRITE OPERATION
// ============================================================================
// The write process is triggered by the rising edge of clk.
//
// Reset behavior:
//   Reset the write pointer to address zero.
//
// Normal operation:
//   If wr_accept is asserted:
//     1. Store data_in at the current write address.
//     2. Wrap the pointer to zero at the final valid address.
//     3. Otherwise, increment the write pointer.
//
// The memory itself is not explicitly cleared by this reset process.
// ============================================================================

always @(posedge clk) begin

    // Synchronous reset: the write pointer is reset at the rising clock edge.
    if (rst)

        // Point to the first memory location.
        wr_ptr <= {ADDR_WIDTH{1'b0}};

    // Perform a write only when the request is accepted.
    else if (wr_accept) begin

        // Store the input word at the current write-pointer address.
        // The nonblocking assignment updates the memory on the clock edge.
        memory[wr_ptr] <= data_in;

        // Check whether the current address is the last valid memory address.
        if (wr_ptr == DEPTH - 1)

            // Wrap around to address zero after the last entry.
            wr_ptr <= {ADDR_WIDTH{1'b0}};

        else

            // Advance to the next memory address.
            wr_ptr <= wr_ptr + 1'b1;

    end

    // If reset is inactive and no write is accepted, wr_ptr holds its value.

end


// ============================================================================
// SECTION 6: READ OPERATION
// ============================================================================
// The read process is triggered by the rising edge of clk.
//
// Reset behavior:
//   Reset the read pointer and clear the registered output.
//
// Normal operation:
//   If rd_accept is asserted:
//     1. Capture the memory word at the current read address.
//     2. Wrap the read pointer at the final valid address.
//     3. Otherwise, increment the read pointer.
//
// If no read is accepted, rd_ptr and data_out retain their previous values.
// ============================================================================

always @(posedge clk) begin

    // Synchronous reset of the read-side registers.
    if (rst) begin

        // Reset the read pointer to the first memory location.
        rd_ptr <= {ADDR_WIDTH{1'b0}};

        // Clear the registered read-data output.
        data_out <= {DATA_WIDTH{1'b0}};

    end

    // Read data only when the FIFO accepts the read request.
    else if (rd_accept) begin

        // Capture the oldest stored word into the registered output.
        data_out <= memory[rd_ptr];

        // Check whether the current read address is the final valid address.
        if (rd_ptr == DEPTH - 1)

            // Wrap around to the first memory location.
            rd_ptr <= {ADDR_WIDTH{1'b0}};

        else

            // Advance to the next memory location.
            rd_ptr <= rd_ptr + 1'b1;

    end

    // If no read is accepted, the read pointer and output data hold steady.

end


// ============================================================================
// SECTION 7: FIFO OCCUPANCY COUNTER
// ============================================================================
// The count register tracks the number of stored FIFO entries.
//
// Counter update rules:
//   wr_accept = 1, rd_accept = 0 : Increment count.
//   wr_accept = 0, rd_accept = 1 : Decrement count.
//   wr_accept = 1, rd_accept = 1 : Keep count unchanged.
//   wr_accept = 0, rd_accept = 0 : Keep count unchanged.
//
// Boundary behavior:
//   At full, a simultaneous read and write accepts only the read because
//   wr_accept is blocked by full.
//   At empty, a simultaneous read and write accepts only the write because
//   rd_accept is blocked by empty.
//
// The counter is updated synchronously with clk.
// ============================================================================

always @(posedge clk) begin
    // Synchronous active-high reset.
    if (rst) begin
        // Reset occupancy to zero entries.
        count <= {COUNT_WIDTH{1'b0}};
    end
    else begin
        // Examine the pair of accepted operations.
        // The first bit is wr_accept; the second bit is rd_accept.
        case ({wr_accept, rd_accept})
            // Write accepted, read not accepted:
            // One additional entry is stored in the FIFO.
            2'b10: count <= count + 1'b1;
            // Read accepted, write not accepted:
            // One entry is removed from the FIFO.
            2'b01: count <= count - 1'b1;
            // Both operations accepted:
            // One entry is added and one entry is removed.
            // Therefore, occupancy does not change.
            2'b11, 2'b00: count <= count;
            // Neither operation is accepted:
            // Occupancy remains unchanged.
            default: count <= count;
        endcase
    end
end
endmodule
