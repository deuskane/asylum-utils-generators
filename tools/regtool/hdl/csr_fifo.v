//-----------------------------------------------------------------------------
// Title      : csr_fifo
// Project    : regtool
//-----------------------------------------------------------------------------
// File       : csr_fifo.v
// Author     : Mathieu Rosiere
// Company    :
// Created    : 2026-10-23
// Platform   :
// Standard   : Verilog 2005
//-----------------------------------------------------------------------------
// Description:
//  Verilog version of csr_fifo.vhd : interface from csr to FIFO
//  csr_fifo_sync (csr_fifo_sync.v) replaces fifo_sync (asylum:component:fifo)
//-----------------------------------------------------------------------------
// Copyright (c) 2026
//-----------------------------------------------------------------------------
// Revisions  :
// Date        Version  Author   Description
// 2026-10-23  1.0      mrosiere Created
//-----------------------------------------------------------------------------

module csr_fifo
  #(parameter WIDTH          = 1                      // Data Width
   ,parameter BLOCKING_READ  = 0                      // 1 : sw_rbusy_o while the HW2SW side is empty
   ,parameter BLOCKING_WRITE = 1                      // 1 : sw_wbusy_o while the SW2HW side is full
   ,parameter DEPTH_SW2HW    = 0                      // 0 : direct connection
   ,parameter DEPTH_HW2SW    = 0                      // 0 : direct connection
   )
  (
    // Clock & Reset (not used if DEPTH_SW2HW = DEPTH_HW2SW = 0)
    // verilator lint_off UNUSEDSIGNAL
    input  wire             clk_i                     // Clock
   ,input  wire             arst_b_i                  // Asynchronous Reset active low
    // verilator lint_on UNUSEDSIGNAL

    // Software Side
   ,input  wire [WIDTH-1:0] sw_wd_i                   // Software Side Write Data
   ,output wire [WIDTH-1:0] sw_rd_o                   // Software Side Read  Data
   ,input  wire             sw_we_i                   // Software Side Write Enable
   ,input  wire             sw_re_i                   // Software Side Read  Enable
   ,output wire             sw_rbusy_o                // Software Side Read  Busy
   ,output wire             sw_wbusy_o                // Software Side Write Busy

    // Hardware Side
   ,input  wire             hw_tx_valid_i             // Hardware Side TX Valid
   ,output wire             hw_tx_ready_o             // Hardware Side TX Ready
   ,input  wire [WIDTH-1:0] hw_tx_data_i              // Hardware Side TX Data
   ,output wire             hw_tx_empty_o             // Hardware Side TX Empty Flag
   ,output wire             hw_tx_full_o              // Hardware Side TX Full  Flag

   ,output wire             hw_rx_valid_o             // Hardware Side RX Valid
   ,input  wire             hw_rx_ready_i             // Hardware Side RX Ready
   ,output wire [WIDTH-1:0] hw_rx_data_o              // Hardware Side RX Data
   ,output wire             hw_rx_empty_o             // Hardware Side RX Empty Flag
   ,output wire             hw_rx_full_o              // Hardware Side RX Full  Flag
   );

  wire full;
  wire empty;
  // Used only by a direct connection (depth 0)
  // verilator lint_off UNUSEDSIGNAL
  wire full_b;
  wire empty_b;
  // verilator lint_on UNUSEDSIGNAL

  // Unused FIFO flags are left open
  // verilator lint_off PINCONNECTEMPTY
  generate
    if (DEPTH_SW2HW == 0)
      begin : gen_depth_sw2hw_eq_0
        assign hw_rx_valid_o = sw_we_i;
        assign hw_rx_data_o  = sw_wd_i;

        assign full_b        = hw_rx_ready_i;
        assign full          = ~full_b;

        assign hw_rx_empty_o = full_b;
        assign hw_rx_full_o  = full;
      end
    else
      begin : gen_depth_sw2hw_ne_0
        csr_fifo_sync
          #(.WIDTH          (WIDTH)
           ,.DEPTH          (DEPTH_SW2HW)
           )
        ins_fifo_sw2hw
          (.clk_i           (clk_i)
          ,.arst_b_i        (arst_b_i)
          ,.s_valid_i       (sw_we_i)
          ,.s_ready_o       (full_b)
          ,.s_data_i        (sw_wd_i)
          ,.s_full_o        (full)
          ,.s_empty_o       ()
          ,.m_valid_o       (hw_rx_valid_o)
          ,.m_ready_i       (hw_rx_ready_i)
          ,.m_data_o        (hw_rx_data_o)
          ,.m_full_o        (hw_rx_full_o)
          ,.m_empty_o       (hw_rx_empty_o)
          );
      end

    if (DEPTH_HW2SW == 0)
      begin : gen_depth_hw2sw_eq_0
        assign hw_tx_ready_o = sw_re_i;
        assign sw_rd_o       = hw_tx_data_i;      // Unmasked Read

        assign empty_b       = hw_tx_valid_i;
        assign empty         = ~empty_b;

        assign hw_tx_empty_o = empty;
        assign hw_tx_full_o  = empty_b;
      end
    else
      begin : gen_depth_hw2sw_ne_0
        csr_fifo_sync
          #(.WIDTH          (WIDTH)
           ,.DEPTH          (DEPTH_HW2SW)
           )
        ins_fifo_hw2sw
          (.clk_i           (clk_i)
          ,.arst_b_i        (arst_b_i)
          ,.s_valid_i       (hw_tx_valid_i)
          ,.s_ready_o       (hw_tx_ready_o)
          ,.s_data_i        (hw_tx_data_i)
          ,.s_full_o        (hw_tx_full_o)
          ,.s_empty_o       (hw_tx_empty_o)
          ,.m_valid_o       (empty_b)
          ,.m_ready_i       (sw_re_i)
          ,.m_data_o        (sw_rd_o)
          ,.m_full_o        ()
          ,.m_empty_o       (empty)
          );
      end
  endgenerate
  // verilator lint_on PINCONNECTEMPTY

  assign sw_wbusy_o = BLOCKING_WRITE ? full  : 1'b0;
  assign sw_rbusy_o = BLOCKING_READ  ? empty : 1'b0;

endmodule
