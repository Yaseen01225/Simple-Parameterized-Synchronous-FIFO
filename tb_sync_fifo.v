
`timescale 1ns / 1ps

// ============================================================================
// Project   : Simple Parameterized Synchronous FIFO
// File      : tb_sync_fifo.v
// Developer : Ghulam Yaseen Nangraj
// Date      : 2026-10-30
// Platform  : Xilinx Vivado 2025.2.1 / xsim
// Language  : Verilog-2001
//
// Purpose:
//   Verify reset, FIFO writes, full/empty flags, read ordering,
//   rejected operations, and internal memory visibility.
//
// Notes:
//   No for, while, or repeat loops are used.
//   The DUT memory is observed through hierarchical references.
// ============================================================================

module tb_sync_fifo;

    // ========================================================================
    // 1. PARAMETERS
    // ========================================================================

    parameter DATA_WIDTH = 8;
    parameter DEPTH      = 4;

    // ========================================================================
    // 2. TESTBENCH SIGNALS
    // ========================================================================

    reg clk;
    reg rst;

    reg                  wr_en;
    reg [DATA_WIDTH-1:0] data_in;

    reg                  rd_en;
    wire [DATA_WIDTH-1:0] data_out;

    wire full;
    wire empty;
    wire [2:0] count;

    integer tests_passed;
    integer tests_failed;

    // ========================================================================
    // 3. DUT INSTANTIATION
    // ========================================================================

    sync_fifo #(
        .DATA_WIDTH(DATA_WIDTH),
        .DEPTH(DEPTH)
    ) dut (
        .clk(clk),
        .rst(rst),
        .wr_en(wr_en),
        .data_in(data_in),
        .rd_en(rd_en),
        .data_out(data_out),
        .full(full),
        .empty(empty),
        .count(count)
    );

    // ========================================================================
    // 4. INTERNAL FIFO MEMORY VIEW
    // ========================================================================
    // These aliases allow the four memory locations to be added to the
    // Vivado waveform window. This section is for observation only.

    wire [DATA_WIDTH-1:0] mem_view [0:DEPTH-1];

    assign mem_view[0] = dut.memory[0];
    assign mem_view[1] = dut.memory[1];
    assign mem_view[2] = dut.memory[2];
    assign mem_view[3] = dut.memory[3];

    // ========================================================================
    // 5. CLOCK GENERATION
    // ========================================================================

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // ========================================================================
    // 6. SELF-CHECKING TASK
    // ========================================================================

    task check_result;
        input condition;
        input [8*100-1:0] test_name;
        begin
            if (condition === 1'b1) begin
                tests_passed = tests_passed + 1;
                $display("[PASS] %0s", test_name);
            end
            else begin
                tests_failed = tests_failed + 1;
                $display("[FAIL] %0s", test_name);
            end
        end
    endtask

    // ========================================================================
    // 7. WRITE TASK
    // ========================================================================
    // Apply inputs at the falling edge. The DUT accepts the write at the
    // following rising edge. Deassert wr_en before another write can occur.

    task write_data;
        input [DATA_WIDTH-1:0] value;
        begin
            @(negedge clk);
            wr_en   = 1'b1;
            rd_en   = 1'b0;
            data_in = value;

            @(posedge clk);
            #1;

            $display(
                "WRITE: input=0x%0h count=%0d full=%b mem[0]=0x%0h mem[1]=0x%0h mem[2]=0x%0h mem[3]=0x%0h",
                data_in, count,
                full,
                mem_view[0], mem_view[1],
                mem_view[2], mem_view[3]
            );

            wr_en = 1'b0;
        end
    endtask

    // ========================================================================
    // 8. READ AND CHECK TASK
    // ========================================================================
    // The FIFO updates data_out using a nonblocking assignment at the
    // rising edge. Wait #1 before comparing the returned value.

    task read_and_check;
        input [DATA_WIDTH-1:0] expected_data;
        begin
            @(negedge clk);
            wr_en = 1'b0;
            rd_en = 1'b1;

            @(posedge clk);
            #1;

            $display(
                "READ: expected=0x%0h actual=0x%0h count=%0d empty=%b rd_ptr=%0d",
                expected_data, data_out, count, empty, dut.rd_ptr
            );

            if (data_out === expected_data) begin
                tests_passed = tests_passed + 1;
                $display("[PASS] Read data 0x%0h", data_out);
            end
            else begin
                tests_failed = tests_failed + 1;
                $display(
                    "[FAIL] Read mismatch: expected=0x%0h actual=0x%0h",
                    expected_data, data_out
                );
            end

            rd_en = 1'b0;
        end
    endtask

    // ========================================================================
    // 9. MAIN TEST SEQUENCE
    // ========================================================================

    initial begin

        // Initialize all testbench signals.
        rst         = 1'b1;
        wr_en       = 1'b0;
        rd_en       = 1'b0;
        data_in     = {DATA_WIDTH{1'b0}};
        tests_passed = 0;
        tests_failed = 0;

        $display("");
        $display("==============================================");
        $display(" SYNCHRONOUS FIFO TEST");
        $display(" DATA_WIDTH = %0d", DATA_WIDTH);
        $display(" DEPTH      = %0d", DEPTH);
        $display("==============================================");

        // ---------------------------------------------------------------
        // TEST 1: RESET
        // ---------------------------------------------------------------

        @(posedge clk);
        @(posedge clk);
        @(negedge clk);
        rst = 1'b0;
        #1;

        check_result(
            (empty === 1'b1) &&
            (full  === 1'b0) &&
            (count === 0),
            "Reset: empty=1, full=0, count=0"
        );

        check_result(
            data_out === {DATA_WIDTH{1'b0}},
            "Reset clears data_out"
        );

        // ---------------------------------------------------------------
        // TEST 2: WRITE FOUR VALUES
        // ---------------------------------------------------------------

        write_data(8'h11);
        write_data(8'h22);
        write_data(8'h33);
        write_data(8'h44);

        check_result(
            (full === 1'b1) && (count === DEPTH),
            "FIFO becomes full after four writes"
        );

        check_result(
            (empty === 1'b0),
            "Empty flag deasserts after writes"
        );

        check_result(
            (mem_view[0] === 8'h11) &&
            (mem_view[1] === 8'h22) &&
            (mem_view[2] === 8'h33) &&
            (mem_view[3] === 8'h44),
            "Internal memory contains the four written values"
        );

        // ---------------------------------------------------------------
        // TEST 3: REJECT WRITE WHEN FULL
        // ---------------------------------------------------------------

        @(negedge clk);
        wr_en   = 1'b1;
        rd_en   = 1'b0;
        data_in = 8'h55;

        @(posedge clk);
        #1;
        wr_en = 1'b0;

        check_result(
            (full === 1'b1) && (count === DEPTH),
            "Write while full is rejected"
        );

        check_result(
            (mem_view[0] === 8'h11) &&
            (mem_view[1] === 8'h22) &&
            (mem_view[2] === 8'h33) &&
            (mem_view[3] === 8'h44),
            "Rejected write does not overwrite FIFO memory"
        );

        // ---------------------------------------------------------------
        // TEST 4: READ ALL VALUES IN FIFO ORDER
        // ---------------------------------------------------------------

        read_and_check(8'h11);
        read_and_check(8'h22);
        read_and_check(8'h33);
        read_and_check(8'h44);

        check_result(
            (empty === 1'b1) &&
            (full  === 1'b0) &&
            (count === 0),
            "FIFO becomes empty after four reads"
        );

        // ---------------------------------------------------------------
        // TEST 5: REJECT READ WHEN EMPTY
        // ---------------------------------------------------------------

        @(negedge clk);
        wr_en = 1'b0;
        rd_en = 1'b1;

        @(posedge clk);
        #1;
        rd_en = 1'b0;

        check_result(
            (empty === 1'b1) && (count === 0),
            "Read while empty is rejected"
        );

        // ---------------------------------------------------------------
        // TEST 6: POINTER WRAPAROUND
        // ---------------------------------------------------------------

        write_data(8'hA1);
        write_data(8'hB2);
        write_data(8'hC3);
        write_data(8'hD4);

        check_result(
            (full === 1'b1) && (count === DEPTH),
            "FIFO fills after pointer wraparound"
        );

        read_and_check(8'hA1);
        read_and_check(8'hB2);
        read_and_check(8'hC3);
        read_and_check(8'hD4);

        check_result(
            (empty === 1'b1) && (count === 0),
            "FIFO empties after pointer wraparound"
        );

        // ---------------------------------------------------------------
        // TEST 7: FINAL SUMMARY
        // ---------------------------------------------------------------

        @(negedge clk);

        $display("");
        $display("==============================================");
        $display(" TESTS PASSED : %0d", tests_passed);
        $display(" TESTS FAILED : %0d", tests_failed);
        $display("==============================================");

        if (tests_failed == 0)
            $display("ALL TESTS PASSED");
        else
            $display("TESTBENCH FAILED");

        $display("==============================================");
        $finish;
    end

    // ========================================================================
    // 10. SIMULATION TIMEOUT
    // ========================================================================

    initial begin
        #10000;
        $display("[FAIL] Simulation timeout.");
        $finish;
    end

endmodule
