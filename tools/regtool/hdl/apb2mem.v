//-----------------------------------------------------------------------------
// Title      : apb2mem
// Project    : regtool
//-----------------------------------------------------------------------------
// File       : apb2mem.v
// Author     : Mathieu Rosiere
// Company    :
// Created    : 2026-10-23
// Platform   :
// Standard   : Verilog 2005
//-----------------------------------------------------------------------------
// Description:
//  Verilog version of apb2mem.vhd
//  Bridge from an APB3 completer to the memory interface of the regtool CSR
//  (cs / re / we / addr / wdata / rdata / busy).
//  Combinational : the access is done in the access phase (psel and
//  penable), pready is 0 while the memory interface is busy.
//  pslverr is always 0 (an unmapped address reads 0).
//  APB4 pprot and pstrb are not used (full word writes).
//-----------------------------------------------------------------------------
// Copyright (c) 2026
//-----------------------------------------------------------------------------
// Revisions  :
// Date        Version  Author   Description
// 2026-10-23  1.0      mrosiere Created
//-----------------------------------------------------------------------------

module apb2mem
  #(parameter ADDR_WIDTH = 8                          // Address Width
   ,parameter DATA_WIDTH = 32                         // Data Width
   )
  (
    // APB
    input  wire                  s_apb_psel_i         // Select
   ,input  wire                  s_apb_penable_i      // Enable (access phase)
   ,input  wire                  s_apb_pwrite_i       // 1 : write, 0 : read
   ,input  wire [ADDR_WIDTH-1:0] s_apb_paddr_i        // Address
   ,input  wire [DATA_WIDTH-1:0] s_apb_pwdata_i       // Write Data
   ,output wire [DATA_WIDTH-1:0] s_apb_prdata_o       // Read  Data
   ,output wire                  s_apb_pready_o       // Ready
   ,output wire                  s_apb_pslverr_o      // Error
    // Memory Interface
   ,output wire                  cs_o                 // Chip Select
   ,output wire                  re_o                 // Read  Enable
   ,output wire                  we_o                 // Write Enable
   ,output wire [ADDR_WIDTH-1:0] addr_o               // Address
   ,output wire [DATA_WIDTH-1:0] wdata_o              // Write Data
   ,input  wire [DATA_WIDTH-1:0] rdata_i              // Read  Data
   ,input  wire                  busy_i               // Access not completed
   );

  wire access_phase;

  assign access_phase    = s_apb_psel_i & s_apb_penable_i;

  assign cs_o            = access_phase;
  assign re_o            = access_phase & ~s_apb_pwrite_i;
  assign we_o            = access_phase &  s_apb_pwrite_i;
  assign addr_o          = s_apb_paddr_i;
  assign wdata_o         = s_apb_pwdata_i;

  assign s_apb_prdata_o  = rdata_i;
  assign s_apb_pready_o  = ~busy_i;
  assign s_apb_pslverr_o = 1'b0;

endmodule
