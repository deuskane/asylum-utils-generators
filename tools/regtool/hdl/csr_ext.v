//-----------------------------------------------------------------------------
// Title      : csr_ext
// Project    : regtool
//-----------------------------------------------------------------------------
// File       : csr_ext.v
// Author     : Mathieu Rosiere
// Company    :
// Created    : 2026-10-23
// Platform   :
// Standard   : Verilog 2005
//-----------------------------------------------------------------------------
// Description:
//  Verilog version of csr_ext.vhd
//  Macro from https://opentitan.org/book/util/reggen/index.html
//-----------------------------------------------------------------------------
// Copyright (c) 2026
//-----------------------------------------------------------------------------
// Revisions  :
// Date        Version  Author   Description
// 2026-10-23  1.0      mrosiere Created
//-----------------------------------------------------------------------------

module csr_ext
  #(parameter             WIDTH = 1                   // Register Width
   )
  (
    // Clock, Reset and hw_we_i are not used (no storage)
    // verilator lint_off UNUSEDSIGNAL
    // Clock & Reset
    input  wire             clk_i                     // Clock
   ,input  wire             arst_b_i                  // Asynchronous Reset active low
    // Software Side
   ,input  wire [WIDTH-1:0] sw_wd_i                   // Software Side Write Data
   ,output wire [WIDTH-1:0] sw_rd_o                   // Software Side Read  Data
   ,input  wire             sw_we_i                   // Software Side Write Enable
   ,input  wire             sw_re_i                   // Software Side Read  Enable
   ,output wire             sw_rbusy_o                // Software Side Read  Busy
   ,output wire             sw_wbusy_o                // Software Side Write Busy
    // Hardware Side
   ,input  wire [WIDTH-1:0] hw_wd_i                   // Hardware Side Write Data
   ,output wire [WIDTH-1:0] hw_rd_o                   // Hardware Side Read  Data
   ,input  wire             hw_we_i                   // Hardware Side Write Enable
   ,output wire             hw_sw_re_o                // Hardware Side CSR was Read
   ,output wire             hw_sw_we_o                // Hardware Side CSR was Write
    // verilator lint_on UNUSEDSIGNAL
   );

  assign sw_rbusy_o = 1'b0;
  assign sw_wbusy_o = 1'b0;
  assign sw_rd_o    = hw_wd_i;
  assign hw_rd_o    = sw_wd_i;
  assign hw_sw_re_o = sw_re_i;
  assign hw_sw_we_o = sw_we_i;

endmodule
