//-----------------------------------------------------------------------------
// Title      : tb_regtool
// Project    : regtool
//-----------------------------------------------------------------------------
// File       : tb_regtool.v
// Author     : Mathieu Rosiere
// Company    :
// Created    : 2026-10-23
// Platform   :
// Standard   : Verilog 2005
//-----------------------------------------------------------------------------
// Description:
//  Testbench of the Verilog CSR tbcsr (sim/tbcsr.hjson) generated with the
//  interface ITF ("mem", "apb", "axi4lite"), same scenarios as the VHDL
//  testbenches (tb_regtool_scenario.vhd), one scenario per simulation (TEST),
//  plus "axi_concurrent" (axi4lite : read and write requested together).
//  Prints "[TESTBENCH] Test <TEST> OK" or "[TESTBENCH] ERROR : ..."
//  Run by tests/test_sim_verilog.py (iverilog)
//-----------------------------------------------------------------------------
// Copyright (c) 2026
//-----------------------------------------------------------------------------
// Revisions  :
// Date        Version  Author   Description
// 2026-10-23  1.0      mrosiere Created
//-----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_regtool;

  parameter ITF        = "mem";
  parameter TEST       = "reset";

  localparam AW            = 5;
  localparam DW            = 32;
  localparam FIFO_DELAY    = 20;
  localparam RESP_DELAY    = 2;

  localparam ADDR_CTRL     = 8'h00;
  localparam ADDR_STATUS   = 8'h04;
  localparam ADDR_IRQ      = 8'h08;
  localparam ADDR_CMD      = 8'h0C;
  localparam ADDR_EXT      = 8'h10;
  localparam ADDR_RX       = 8'h14;
  localparam ADDR_TX       = 8'h18;
  localparam ADDR_UNMAPPED = 8'h1C;

  //---------------------------------------------------------------------------
  // Clock and Reset
  //---------------------------------------------------------------------------
  reg clk    = 1'b0;
  reg arst_b = 1'b0;

  always #5 clk = ~clk;
  initial #52 arst_b = 1'b1;

  //---------------------------------------------------------------------------
  // Bus
  //---------------------------------------------------------------------------
  // mem
  reg           cs      = 1'b0;
  reg           re      = 1'b0;
  reg           we      = 1'b0;
  reg  [AW-1:0] addr    = {AW{1'b0}};
  reg  [DW-1:0] wdata   = {DW{1'b0}};
  wire [DW-1:0] rdata;
  wire          busy;
  // apb
  reg           psel    = 1'b0;
  reg           penable = 1'b0;
  reg           pwrite  = 1'b0;
  reg  [AW-1:0] paddr   = {AW{1'b0}};
  reg  [DW-1:0] pwdata  = {DW{1'b0}};
  wire [DW-1:0] prdata;
  wire          pready;
  wire          pslverr;
  // axi4lite
  reg           awvalid = 1'b0;
  wire          awready;
  reg  [AW-1:0] awaddr  = {AW{1'b0}};
  reg           wvalid  = 1'b0;
  wire          wready;
  reg  [DW-1:0] axi_wdata = {DW{1'b0}};
  reg  [DW/8-1:0] wstrb = {DW/8{1'b0}};
  wire          bvalid;
  reg           bready  = 1'b0;
  wire [1:0]    bresp;
  reg           arvalid = 1'b0;
  wire          arready;
  reg  [AW-1:0] araddr  = {AW{1'b0}};
  wire          rvalid;
  reg           rready  = 1'b0;
  wire [DW-1:0] axi_rdata;
  wire [1:0]    rresp;

  //---------------------------------------------------------------------------
  // Hardware side
  //---------------------------------------------------------------------------
  wire          sw2hw_ctrl_re;
  wire          sw2hw_ctrl_we;
  wire          sw2hw_ctrl_en;
  wire [1:0]    sw2hw_ctrl_mode;
  wire [7:0]    sw2hw_ctrl_div;
  wire          sw2hw_status_re;
  reg           hw2sw_status_we    = 1'b0;
  reg           hw2sw_status_busy  = 1'b0;
  reg  [7:0]    hw2sw_status_count = 8'h00;
  wire          sw2hw_irq_re;
  wire          sw2hw_irq_we;
  wire [3:0]    sw2hw_irq_flags;
  reg           hw2sw_irq_we       = 1'b0;
  reg  [3:0]    hw2sw_irq_flags    = 4'h0;
  wire          sw2hw_cmd_we;
  wire [7:0]    sw2hw_cmd_op;
  wire          sw2hw_ext_re;
  wire          sw2hw_ext_we;
  wire [31:0]   sw2hw_ext_data;
  reg           hw2sw_ext_we       = 1'b0;
  reg  [31:0]   hw2sw_ext_data     = 32'hA5A5_0F0F;
  wire          sw2hw_rx_ready;
  wire          sw2hw_rx_hw2sw_empty;
  wire          sw2hw_rx_hw2sw_full;
  reg           hw2sw_rx_valid     = 1'b0;
  reg  [15:0]   hw2sw_rx_data      = 16'h0000;
  wire          sw2hw_tx_valid;
  wire [15:0]   sw2hw_tx_data;
  wire          sw2hw_tx_sw2hw_empty;
  wire          sw2hw_tx_sw2hw_full;
  reg           hw2sw_tx_ready     = 1'b0;

`define TB_CSR_PORTS \
    .clk_i                  (clk),                  \
    .arst_b_i               (arst_b),               \
    .sw2hw_ctrl_re_o        (sw2hw_ctrl_re),        \
    .sw2hw_ctrl_we_o        (sw2hw_ctrl_we),        \
    .sw2hw_ctrl_en_o        (sw2hw_ctrl_en),        \
    .sw2hw_ctrl_mode_o      (sw2hw_ctrl_mode),      \
    .sw2hw_ctrl_div_o       (sw2hw_ctrl_div),       \
    .sw2hw_status_re_o      (sw2hw_status_re),      \
    .hw2sw_status_we_i      (hw2sw_status_we),      \
    .hw2sw_status_busy_i    (hw2sw_status_busy),    \
    .hw2sw_status_count_i   (hw2sw_status_count),   \
    .sw2hw_irq_re_o         (sw2hw_irq_re),         \
    .sw2hw_irq_we_o         (sw2hw_irq_we),         \
    .sw2hw_irq_flags_o      (sw2hw_irq_flags),      \
    .hw2sw_irq_we_i         (hw2sw_irq_we),         \
    .hw2sw_irq_flags_i      (hw2sw_irq_flags),      \
    .sw2hw_cmd_we_o         (sw2hw_cmd_we),         \
    .sw2hw_cmd_op_o         (sw2hw_cmd_op),         \
    .sw2hw_ext_re_o         (sw2hw_ext_re),         \
    .sw2hw_ext_we_o         (sw2hw_ext_we),         \
    .sw2hw_ext_data_o       (sw2hw_ext_data),       \
    .hw2sw_ext_we_i         (hw2sw_ext_we),         \
    .hw2sw_ext_data_i       (hw2sw_ext_data),       \
    .sw2hw_rx_ready_o       (sw2hw_rx_ready),       \
    .sw2hw_rx_hw2sw_empty_o (sw2hw_rx_hw2sw_empty), \
    .sw2hw_rx_hw2sw_full_o  (sw2hw_rx_hw2sw_full),  \
    .hw2sw_rx_valid_i       (hw2sw_rx_valid),       \
    .hw2sw_rx_data_i        (hw2sw_rx_data),        \
    .sw2hw_tx_valid_o       (sw2hw_tx_valid),       \
    .sw2hw_tx_data_o        (sw2hw_tx_data),        \
    .sw2hw_tx_sw2hw_empty_o (sw2hw_tx_sw2hw_empty), \
    .sw2hw_tx_sw2hw_full_o  (sw2hw_tx_sw2hw_full),  \
    .hw2sw_tx_ready_i       (hw2sw_tx_ready)

  //---------------------------------------------------------------------------
  // DUT
  //---------------------------------------------------------------------------
  generate
    if (ITF == "mem")
      begin : gen_mem
        tbcsr_registers ins_dut
          (`TB_CSR_PORTS
          ,.cs_i      (cs)
          ,.re_i      (re)
          ,.we_i      (we)
          ,.addr_i    (addr)
          ,.wdata_i   (wdata)
          ,.rdata_o   (rdata)
          ,.busy_o    (busy)
          );
      end
    else if (ITF == "apb")
      begin : gen_apb
        tbcsr_registers ins_dut
          (`TB_CSR_PORTS
          ,.s_apb_psel_i    (psel)
          ,.s_apb_penable_i (penable)
          ,.s_apb_pwrite_i  (pwrite)
          ,.s_apb_paddr_i   (paddr)
          ,.s_apb_pwdata_i  (pwdata)
          ,.s_apb_prdata_o  (prdata)
          ,.s_apb_pready_o  (pready)
          ,.s_apb_pslverr_o (pslverr)
          );
      end
    else
      begin : gen_axi4lite
        tbcsr_registers ins_dut
          (`TB_CSR_PORTS
          ,.s_axi_awvalid_i (awvalid)
          ,.s_axi_awready_o (awready)
          ,.s_axi_awaddr_i  (awaddr)
          ,.s_axi_wvalid_i  (wvalid)
          ,.s_axi_wready_o  (wready)
          ,.s_axi_wdata_i   (axi_wdata)
          ,.s_axi_wstrb_i   (wstrb)
          ,.s_axi_bvalid_o  (bvalid)
          ,.s_axi_bready_i  (bready)
          ,.s_axi_bresp_o   (bresp)
          ,.s_axi_arvalid_i (arvalid)
          ,.s_axi_arready_o (arready)
          ,.s_axi_araddr_i  (araddr)
          ,.s_axi_rvalid_o  (rvalid)
          ,.s_axi_rready_i  (rready)
          ,.s_axi_rdata_o   (axi_rdata)
          ,.s_axi_rresp_o   (rresp)
          );
      end
  endgenerate

  //---------------------------------------------------------------------------
  // Checks
  //---------------------------------------------------------------------------
  integer errors = 0;

  task check;
    input       cond;
    input [8*48-1:0] msg;
    begin
      if (!cond)
        begin
          $display("[TESTBENCH] ERROR : %0s", msg);
          errors = errors + 1;
          $finish;
        end
    end
  endtask

  task check_equal;
    input [DW-1:0]   value;
    input [DW-1:0]   expected;
    input [8*48-1:0] msg;
    begin
      if (value !== expected)
        begin
          $display("[TESTBENCH] ERROR : %0s : 0x%h instead of 0x%h", msg, value, expected);
          errors = errors + 1;
          $finish;
        end
    end
  endtask

  //---------------------------------------------------------------------------
  // Bus masters : the access is done on the rising edge where the target is
  // ready (values sampled before the edge)
  //---------------------------------------------------------------------------
  reg [DW-1:0] rd;                                    // Read data of the last access
  integer      cycles;                                // Clock cycles of the last access

  task mem_access;
    input          write;
    input [7:0]    a;
    input [DW-1:0] d;
    begin
      cs     <= 1'b1;
      re     <= !write;
      we     <=  write;
      addr   <= a[AW-1:0];
      wdata  <= d;
      cycles  = 0;
      @(posedge clk); cycles = cycles + 1;
      while (busy)
        begin
          @(posedge clk); cycles = cycles + 1;
        end
      rd      = rdata;
      cs     <= 1'b0;
      re     <= 1'b0;
      we     <= 1'b0;
    end
  endtask

  task apb_access;
    input          write;
    input [7:0]    a;
    input [DW-1:0] d;
    begin
      // Setup phase
      psel    <= 1'b1;
      pwrite  <= write;
      paddr   <= a[AW-1:0];
      pwdata  <= d;
      cycles   = 0;
      @(posedge clk); cycles = cycles + 1;
      // Access phase, until pready
      penable <= 1'b1;
      @(posedge clk); cycles = cycles + 1;
      while (!pready)
        begin
          @(posedge clk); cycles = cycles + 1;
        end
      check(!pslverr, "APB pslverr");
      rd       = prdata;
      psel    <= 1'b0;
      penable <= 1'b0;
    end
  endtask

  // AXI4-Lite write : AW, then W one cycle later (the subordinate must wait for both)
  task axi_write;
    input [7:0]    a;
    input [DW-1:0] d;
    integer        n;
    reg            aw_done;
    reg            w_done;
    begin
      awvalid   <= 1'b1;
      awaddr    <= a[AW-1:0];
      n          = 0;
      @(posedge clk); n = n + 1;
      check(!awready, "AXI awready before wvalid");
      wvalid    <= 1'b1;
      axi_wdata <= d;
      wstrb     <= {DW/8{1'b1}};
      aw_done    = 1'b0;
      w_done     = 1'b0;
      while (!(aw_done && w_done))
        begin
          @(posedge clk); n = n + 1;
          if (awready) begin aw_done = 1'b1; awvalid <= 1'b0; end
          if (wready ) begin w_done  = 1'b1; wvalid  <= 1'b0; end
        end
      // Write response, bready RESP_DELAY cycles after bvalid
      @(posedge clk); n = n + 1;
      while (!bvalid)
        begin
          @(posedge clk); n = n + 1;
        end
      repeat (RESP_DELAY)
        begin
          @(posedge clk); n = n + 1;
          check(bvalid, "AXI bvalid not held");
        end
      bready    <= 1'b1;
      @(posedge clk); n = n + 1;
      check(bvalid        , "AXI bvalid not held");
      check(bresp == 2'b00, "AXI bresp not OKAY");
      bready    <= 1'b0;
      cycles     = n;
    end
  endtask

  // AXI4-Lite read, rready RESP_DELAY cycles after rvalid
  task axi_read;
    input  [7:0]    a;
    output [DW-1:0] q;
    integer         n;
    begin
      arvalid   <= 1'b1;
      araddr    <= a[AW-1:0];
      n          = 0;
      @(posedge clk); n = n + 1;
      while (!arready)
        begin
          @(posedge clk); n = n + 1;
        end
      arvalid   <= 1'b0;
      @(posedge clk); n = n + 1;
      while (!rvalid)
        begin
          @(posedge clk); n = n + 1;
        end
      q          = axi_rdata;
      repeat (RESP_DELAY)
        begin
          @(posedge clk); n = n + 1;
          check(rvalid, "AXI rvalid not held");
        end
      rready    <= 1'b1;
      @(posedge clk); n = n + 1;
      check      (rvalid        , "AXI rvalid not held");
      check_equal(axi_rdata, q  , "AXI rdata not held");
      check      (rresp == 2'b00, "AXI rresp not OKAY");
      rready    <= 1'b0;
      cycles     = n;
    end
  endtask

  task sw_access;
    input          write;
    input [7:0]    a;
    input [DW-1:0] d;
    begin
      if      (ITF == "mem") mem_access(write, a, d);
      else if (ITF == "apb") apb_access(write, a, d);
      else if (write)        axi_write (a, d);
      else                   axi_read  (a, rd);
    end
  endtask

  task sw_write;
    input [7:0]    a;
    input [DW-1:0] d;
    begin
      $display("[TESTBENCH] Write 0x%h <= 0x%h", a, d);
      sw_access(1'b1, a, d);
    end
  endtask

  task sw_check;
    input [7:0]      a;
    input [DW-1:0]   expected;
    input [8*48-1:0] msg;
    begin
      sw_access(1'b0, a, {DW{1'b0}});
      $display("[TESTBENCH] Read  0x%h => 0x%h", a, rd);
      check_equal(rd, expected, msg);
    end
  endtask

  //---------------------------------------------------------------------------
  // Monitors of the hardware side
  //---------------------------------------------------------------------------
  integer      ctrl_we_cnt  = 0;
  integer      cmd_we_cnt   = 0;
  reg [7:0]    cmd_op       = 8'h00;
  integer      ext_we_cnt   = 0;
  reg [31:0]   ext_wdata    = 32'h0;
  integer      rx_push_cnt  = 0;
  integer      tx_pop_cnt   = 0;
  reg [15:0]   tx_pop_data0 = 16'h0;
  reg [15:0]   tx_pop_data1 = 16'h0;
  reg          fifo_go      = 1'b0;

  always @(posedge clk)
    begin
      if (sw2hw_ctrl_we) ctrl_we_cnt <= ctrl_we_cnt + 1;
      if (sw2hw_cmd_we)
        begin
          cmd_we_cnt <= cmd_we_cnt + 1;
          cmd_op     <= sw2hw_cmd_op;
        end
      if (sw2hw_ext_we)
        begin
          ext_we_cnt <= ext_we_cnt + 1;
          ext_wdata  <= sw2hw_ext_data;
        end
      if (sw2hw_rx_ready && hw2sw_rx_valid) rx_push_cnt <= rx_push_cnt + 1;
      if (sw2hw_tx_valid && hw2sw_tx_ready)
        begin
          tx_pop_cnt <= tx_pop_cnt + 1;
          if (tx_pop_cnt == 0) tx_pop_data0 <= sw2hw_tx_data;
          else                 tx_pop_data1 <= sw2hw_tx_data;
        end
    end

  //---------------------------------------------------------------------------
  // Hardware side of the FIFO (rx push, tx pop)
  //---------------------------------------------------------------------------
  task push;
    input [15:0] d;
    begin
      hw2sw_rx_valid <= 1'b1;
      hw2sw_rx_data  <= d;
      @(posedge clk);
      while (!sw2hw_rx_ready) @(posedge clk);
      hw2sw_rx_valid <= 1'b0;
    end
  endtask

  initial
    begin
      wait (arst_b);
      if (TEST == "fifo_read")
        begin
          // First data FIFO_DELAY cycles after the reset (blocking read)
          repeat (FIFO_DELAY) @(posedge clk);
          push(16'h0077);
          // Then two data back to back (FIFO full)
          wait (fifo_go);
          @(posedge clk);
          push(16'h0011);
          push(16'h0022);
        end
      if (TEST == "fifo_write")
        begin
          // Pop FIFO_DELAY cycles after the second software write is started
          wait (fifo_go);
          repeat (FIFO_DELAY) @(posedge clk);
          hw2sw_tx_ready <= 1'b1;
        end
    end

  //---------------------------------------------------------------------------
  // Watchdog
  //---------------------------------------------------------------------------
  initial
    begin
      #100000;
      check(1'b0, "Timeout");
    end

  //---------------------------------------------------------------------------
  // Scenario
  //---------------------------------------------------------------------------
  reg [DW-1:0] rd_concurrent;

  initial
    begin
      $display("[TESTBENCH] Test %0s, interface %0s", TEST, ITF);
      wait (arst_b);
      repeat (2) @(posedge clk);

      //-----------------------------------------------------------------------
      if (TEST == "reset")
        begin
          // Bus
          sw_check(ADDR_CTRL  , 32'h0000_1021, "ctrl reset value");
          sw_check(ADDR_STATUS, 32'h0000_0000, "status reset value");
          sw_check(ADDR_IRQ   , 32'h0000_0000, "irq reset value");
          sw_check(ADDR_CMD   , 32'h0000_0000, "cmd (write only) read");
          sw_check(ADDR_EXT   , 32'hA5A5_0F0F, "ext read (hardware value)");
          // Hardware side
          check_equal(sw2hw_ctrl_en  , 1'b1 , "sw2hw ctrl.en reset value");
          check_equal(sw2hw_ctrl_mode, 2'b10, "sw2hw ctrl.mode reset value");
          check_equal(sw2hw_ctrl_div , 8'h10, "sw2hw ctrl.div reset value");
          check_equal(sw2hw_cmd_op   , 8'h00, "sw2hw cmd.op reset value");
          check(sw2hw_rx_hw2sw_empty, "rx FIFO empty after reset");
          check(sw2hw_tx_sw2hw_empty, "tx FIFO empty after reset");
          check(ctrl_we_cnt == 0 && cmd_we_cnt == 0 && ext_we_cnt == 0, "no write strobe");
        end

      //-----------------------------------------------------------------------
      else if (TEST == "write_read")
        begin
          // Read / write register : only the field bits are stored
          sw_write(ADDR_CTRL  , 32'hFFFF_AB31);
          sw_check(ADDR_CTRL  , 32'h0000_AB31, "ctrl read back");
          @(posedge clk);
          check_equal(sw2hw_ctrl_en  , 1'b1 , "sw2hw ctrl.en");
          check_equal(sw2hw_ctrl_mode, 2'b11, "sw2hw ctrl.mode");
          check_equal(sw2hw_ctrl_div , 8'hAB, "sw2hw ctrl.div");
          check(ctrl_we_cnt == 1, "one ctrl write strobe");

          sw_write(ADDR_CTRL  , 32'h0000_0000);
          sw_check(ADDR_CTRL  , 32'h0000_0000, "ctrl read back");

          // Write only register : the hardware gets the value, the software reads 0
          sw_write(ADDR_CMD   , 32'h0000_005A);
          sw_check(ADDR_CMD   , 32'h0000_0000, "cmd (write only) read");
          @(posedge clk);
          check(cmd_we_cnt == 1, "one cmd write strobe");
          check_equal(cmd_op      , 8'h5A, "cmd.op at the write strobe");
          check_equal(sw2hw_cmd_op, 8'h5A, "sw2hw cmd.op");
        end

      //-----------------------------------------------------------------------
      else if (TEST == "hw_write")
        begin
          // Read only register written by the hardware
          hw2sw_status_we    <= 1'b1;
          hw2sw_status_busy  <= 1'b1;
          hw2sw_status_count <= 8'h42;
          @(posedge clk);
          hw2sw_status_we    <= 1'b0;
          hw2sw_status_count <= 8'h00;
          sw_check(ADDR_STATUS, 32'h0000_0421, "status written by the hardware");
          // The software can not write a read only register
          sw_write(ADDR_STATUS, 32'hFFFF_FFFF);
          sw_check(ADDR_STATUS, 32'h0000_0421, "status after a software write");

          // rw1c : flags set by the hardware, cleared by writing 1
          hw2sw_irq_we       <= 1'b1;
          hw2sw_irq_flags    <= 4'b1010;
          @(posedge clk);
          hw2sw_irq_we       <= 1'b0;
          sw_check(ADDR_IRQ   , 32'h0000_000A, "irq set by the hardware");
          sw_write(ADDR_IRQ   , 32'h0000_0002);
          sw_check(ADDR_IRQ   , 32'h0000_0008, "irq after clearing bit 1");
          sw_write(ADDR_IRQ   , 32'h0000_0000);
          sw_check(ADDR_IRQ   , 32'h0000_0008, "irq after writing 0");
          sw_write(ADDR_IRQ   , 32'hFFFF_FFFF);
          sw_check(ADDR_IRQ   , 32'h0000_0000, "irq after clearing all");
        end

      //-----------------------------------------------------------------------
      else if (TEST == "ext")
        begin
          // External register : read data from the hardware
          hw2sw_ext_data <= 32'h1234_5678;
          @(posedge clk);
          sw_check(ADDR_EXT   , 32'h1234_5678, "ext read");
          hw2sw_ext_data <= 32'h8765_4321;
          @(posedge clk);
          sw_check(ADDR_EXT   , 32'h8765_4321, "ext read");

          // Write data to the hardware with the write strobe
          sw_write(ADDR_EXT   , 32'hDEAD_BEEF);
          @(posedge clk);
          check(ext_we_cnt == 1, "one ext write strobe");
          check_equal(ext_wdata, 32'hDEAD_BEEF, "ext data at the write strobe");
        end

      //-----------------------------------------------------------------------
      else if (TEST == "fifo_read")
        begin
          // Blocking read of the empty FIFO : wait states until the hardware push
          check(sw2hw_rx_hw2sw_empty, "rx FIFO empty");
          sw_check(ADDR_RX    , 32'h0000_0077, "rx first data");
          check(cycles > FIFO_DELAY/2, "rx blocking read : no wait state");
          check(rx_push_cnt == 1, "one rx push");

          // Two data in the FIFO (depth 2), read in order
          fifo_go = 1'b1;
          wait (rx_push_cnt == 3);
          @(posedge clk);
          check(sw2hw_rx_hw2sw_full, "rx FIFO full");
          sw_check(ADDR_RX    , 32'h0000_0011, "rx second data");
          sw_check(ADDR_RX    , 32'h0000_0022, "rx third data");
          @(posedge clk);
          check(sw2hw_rx_hw2sw_empty, "rx FIFO empty");
        end

      //-----------------------------------------------------------------------
      else if (TEST == "fifo_write")
        begin
          // First write in the FIFO (depth 1, the hardware does not pop)
          sw_write(ADDR_TX    , 32'h0000_0101);
          @(posedge clk);
          check(sw2hw_tx_sw2hw_full, "tx FIFO full");
          check(sw2hw_tx_valid     , "tx valid");
          check_equal(sw2hw_tx_data, 16'h0101, "tx data");

          // Blocking write of the full FIFO : wait states until the hardware pop
          fifo_go = 1'b1;
          sw_write(ADDR_TX    , 32'h0000_0202);
          check(cycles > FIFO_DELAY/2, "tx blocking write : no wait state");
          wait (tx_pop_cnt == 2);
          check_equal(tx_pop_data0, 16'h0101, "tx first pop");
          check_equal(tx_pop_data1, 16'h0202, "tx second pop");
        end

      //-----------------------------------------------------------------------
      else if (TEST == "unmapped")
        begin
          // Unmapped address : read 0, write without effect
          sw_check(ADDR_UNMAPPED, 32'h0000_0000, "unmapped read");
          sw_write(ADDR_UNMAPPED, 32'hFFFF_FFFF);
          sw_check(ADDR_CTRL    , 32'h0000_1021, "ctrl after an unmapped write");
          sw_check(ADDR_IRQ     , 32'h0000_0000, "irq after an unmapped write");
          @(posedge clk);
          check(ctrl_we_cnt == 0 && cmd_we_cnt == 0 && ext_we_cnt == 0, "no write strobe");
        end

      //-----------------------------------------------------------------------
      else if (TEST == "axi_concurrent" && ITF == "axi4lite")
        begin
          // Write (AW and W) and read (AR) requested together, round robin :
          // the access type not done last wins, both accesses complete.
          // AR one cycle after AW, at the same time as W.
          // After reset : the write wins
          fork
            axi_write(ADDR_CTRL, 32'h0000_0110);
            begin
              @(posedge clk);
              axi_read (ADDR_CTRL, rd_concurrent);
            end
          join
          check_equal(rd_concurrent, 32'h0000_0110, "read after the write");
          // Last access is a write (no effect) : the read wins
          sw_write(ADDR_IRQ   , 32'h0000_0000);
          fork
            axi_write(ADDR_CTRL, 32'h0000_0220);
            begin
              @(posedge clk);
              axi_read (ADDR_CTRL, rd_concurrent);
            end
          join
          check_equal(rd_concurrent, 32'h0000_0110, "read before the write (round robin)");
          sw_check(ADDR_CTRL  , 32'h0000_0220, "ctrl after the second write");
        end

      //-----------------------------------------------------------------------
      else
        check(1'b0, "Unknown test");

      $display("[TESTBENCH] Test %0s OK", TEST);
      $finish;
    end

endmodule
