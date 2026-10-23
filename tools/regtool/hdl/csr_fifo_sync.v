//-----------------------------------------------------------------------------
// Title      : csr_fifo_sync
// Project    : regtool
//-----------------------------------------------------------------------------
// File       : csr_fifo_sync.v
// Author     : Mathieu Rosiere
// Company    : 
// Created    : 2026-10-23
// Platform   : 
// Standard   : Verilog 2005
//-----------------------------------------------------------------------------
// Description:
//  Synchronous FIFO of csr_fifo.v (fifo_sync of asylum:component:fifo with
//  an asynchronous read) : first word fall through (m_data_o valid when
//  m_valid_o), push when not full, pop when not empty, any DEPTH >= 1
//-----------------------------------------------------------------------------
// Copyright (c) 2026 
//-----------------------------------------------------------------------------
// Revisions  :
// Date        Version  Author   Description
// 2026-10-23  1.0      mrosiere Created
//-----------------------------------------------------------------------------

module csr_fifo_sync
  #(parameter WIDTH = 1                               // Data Width
   ,parameter DEPTH = 1                               // Number of words
   )
  (
    input  wire             clk_i                     // Clock
   ,input  wire             arst_b_i                  // Asynchronous Reset active low
    // Push
   ,input  wire             s_valid_i
   ,output wire             s_ready_o                 // Not full
   ,input  wire [WIDTH-1:0] s_data_i
   ,output wire             s_full_o
   ,output wire             s_empty_o
    // Pop
   ,output wire             m_valid_o                 // Not empty
   ,input  wire             m_ready_i
   ,output wire [WIDTH-1:0] m_data_o
   ,output wire             m_full_o
   ,output wire             m_empty_o
   );

  localparam                 IDX_WIDTH = (DEPTH > 1) ? $clog2(DEPTH) : 1;
  localparam [31:0]          DEPTH_32  = DEPTH;
  localparam [31:0]          LAST_32   = DEPTH-1;
  localparam [IDX_WIDTH  :0] NB_FULL   = DEPTH_32[IDX_WIDTH  :0];
  localparam [IDX_WIDTH  :0] NB_EMPTY  = {(IDX_WIDTH+1){1'b0}};
  localparam [IDX_WIDTH-1:0] IDX_FIRST = {IDX_WIDTH{1'b0}};
  localparam [IDX_WIDTH-1:0] IDX_LAST  = LAST_32 [IDX_WIDTH-1:0];

  reg  [WIDTH-1:0]     mem [0:DEPTH-1];
  reg  [IDX_WIDTH-1:0] rd_idx_r;
  reg  [IDX_WIDTH-1:0] wr_idx_r;
  reg  [IDX_WIDTH  :0] count_r;

  wire                 full;
  wire                 empty;
  wire                 push;
  wire                 pop;

  assign full  = (count_r == NB_FULL);
  assign empty = (count_r == NB_EMPTY);
  assign push  = s_valid_i & ~full;
  assign pop   = m_ready_i & ~empty;

  always @(posedge clk_i)
    if (push)
      mem[wr_idx_r] <= s_data_i;

  always @(posedge clk_i or negedge arst_b_i)
    if (!arst_b_i)
      begin
        rd_idx_r <= IDX_FIRST;
        wr_idx_r <= IDX_FIRST;
        count_r  <= NB_EMPTY;
      end
    else
      begin
        if (push)
          wr_idx_r <= (wr_idx_r == IDX_LAST) ? IDX_FIRST : wr_idx_r + 1'b1;
        if (pop)
          rd_idx_r <= (rd_idx_r == IDX_LAST) ? IDX_FIRST : rd_idx_r + 1'b1;
        if (push & ~pop)
          count_r  <= count_r + 1'b1;
        else if (pop & ~push)
          count_r  <= count_r - 1'b1;
      end

  assign s_ready_o = ~full;
  assign s_full_o  = full;
  assign s_empty_o = empty;
  assign m_valid_o = ~empty;
  assign m_data_o  = mem[rd_idx_r];
  assign m_full_o  = full;
  assign m_empty_o = empty;

endmodule
