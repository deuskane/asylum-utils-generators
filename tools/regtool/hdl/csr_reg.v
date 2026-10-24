//-----------------------------------------------------------------------------
// Title      : csr_reg
// Project    : regtool
//-----------------------------------------------------------------------------
// File       : csr_reg.v
// Author     : Mathieu Rosiere
// Company    :
// Created    : 2026-10-23
// Platform   :
// Standard   : Verilog 2005
//-----------------------------------------------------------------------------
// Description:
//  Verilog version of csr_reg.vhd
//  Macro from https://opentitan.org/book/util/reggen/index.html
//-----------------------------------------------------------------------------
// Copyright (c) 2026
//-----------------------------------------------------------------------------
// Revisions  :
// Date        Version  Author   Description
// 2026-10-23  1.0      mrosiere Created
//-----------------------------------------------------------------------------

module csr_reg
  #(parameter             WIDTH = 1                   // Register Width
   ,parameter [WIDTH-1:0] INIT  = {WIDTH{1'b0}}       // Reset
   ,parameter             MODEL = "rw"                // "ro", "rw", "wo", "rw1c", "rw0c", "rw1s", "rw0s", "rsw1c", "rcw1s", "rsw0c"
   )
  (
    // Clock & Reset
    input  wire             clk_i                     // Clock
   ,input  wire             arst_b_i                  // Asynchronous Reset active low
    // Software Side
    // verilator lint_off UNUSEDSIGNAL
   ,input  wire [WIDTH-1:0] sw_wd_i                   // Software Side Write Data (not used by "ro")
    // verilator lint_on UNUSEDSIGNAL
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
   );

  localparam [WIDTH-1:0] ONES  = {WIDTH{1'b1}};
  localparam [WIDTH-1:0] ZEROS = {WIDTH{1'b0}};

  reg  [WIDTH-1:0] q_r;
  reg              q_sw_we_r;
  reg              q_sw_re_r;
  wire [WIDTH-1:0] q_r_next;
  wire [WIDTH-1:0] d_hw;

  assign d_hw = hw_we_i ? hw_wd_i : q_r;

  generate
    if      (MODEL == "ro")
      begin : gen_ro
        assign q_r_next = d_hw;
      end
    else if (MODEL == "rw")
      begin : gen_rw
        assign q_r_next = sw_we_i ? sw_wd_i : d_hw;
      end
    // Write only : the register stores the software writes like "rw";
    // regtool does not connect sw_rd_o to the read data bus (reads return 0)
    else if (MODEL == "wo")
      begin : gen_wo
        assign q_r_next = sw_we_i ? sw_wd_i : d_hw;
      end
    else if (MODEL == "rw1c")
      begin : gen_rw1c
        assign q_r_next = d_hw & (sw_we_i ? ~sw_wd_i : ONES);
      end
    else if (MODEL == "rw0c")
      begin : gen_rw0c
        assign q_r_next = d_hw & (sw_we_i ?  sw_wd_i : ONES);
      end
    else if (MODEL == "rw1s")
      begin : gen_rw1s
        assign q_r_next = d_hw | (sw_we_i ?  sw_wd_i : ZEROS);
      end
    else if (MODEL == "rw0s")
      begin : gen_rw0s
        assign q_r_next = d_hw | (sw_we_i ? ~sw_wd_i : ZEROS);
      end
    // Hardware Write, then
    // Software Read  (set the bits read at 0, even if hw_we_i = 1), then
    // Software Write (clear)
    else if (MODEL == "rsw1c")
      begin : gen_rsw1c
        assign q_r_next = (d_hw | (sw_re_i ? ~q_r : ZEROS)) & (sw_we_i ? ~sw_wd_i : ONES);
      end
    // Hardware Write, then
    // Software Read  (clear the bits read at 1, even if hw_we_i = 1 :
    //                 a bit set by the hardware during the read is kept), then
    // Software Write (set)
    else if (MODEL == "rcw1s")
      begin : gen_rcw1s
        assign q_r_next = (d_hw & (sw_re_i ? ~q_r : ONES)) | (sw_we_i ?  sw_wd_i : ZEROS);
      end
    // Hardware Write, then
    // Software Read  (set the bits read at 0, even if hw_we_i = 1), then
    // Software Write (clear)
    else if (MODEL == "rsw0c")
      begin : gen_rsw0c
        assign q_r_next = (d_hw | (sw_re_i ? ~q_r : ZEROS)) & (sw_we_i ?  sw_wd_i : ONES);
      end
  endgenerate

  always @(posedge clk_i or negedge arst_b_i)
    if (!arst_b_i)                      // asynchronous reset (active low)
      begin
        q_r       <= INIT;
        q_sw_we_r <= 1'b0;
        q_sw_re_r <= 1'b0;
      end
    else                                // rising clock edge
      begin
        q_r       <= q_r_next;
        q_sw_we_r <= sw_we_i;
        q_sw_re_r <= sw_re_i;
      end

  assign hw_sw_re_o = q_sw_re_r;
  assign hw_sw_we_o = q_sw_we_r;
  assign hw_rd_o    = q_r;
  assign sw_rd_o    = q_r;
  assign sw_rbusy_o = 1'b0;
  assign sw_wbusy_o = 1'b0;

endmodule
