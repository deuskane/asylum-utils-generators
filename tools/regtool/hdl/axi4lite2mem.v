//-----------------------------------------------------------------------------
// Title      : axi4lite2mem
// Project    : regtool
//-----------------------------------------------------------------------------
// File       : axi4lite2mem.v
// Author     : Mathieu Rosiere
// Company    :
// Created    : 2026-10-23
// Platform   :
// Standard   : Verilog 2005
//-----------------------------------------------------------------------------
// Description:
//  Verilog version of axi4lite2mem.vhd
//  Bridge from an AXI4-Lite subordinate to the memory interface of the
//  regtool CSR (cs / re / we / addr / wdata / rdata / busy).
//  One access at a time :
//  - write : AW and W are accepted together (awready = wready), the memory
//            write is held until busy = 0, then the response is sent on B
//  - read  : AR is accepted, the memory read is held until busy = 0, the
//            read data is registered and sent on R
//  - read and write requested at the same time : round robin
//  Responses are always OKAY (an unmapped address reads 0).
//  wstrb is not used (full word writes).
//-----------------------------------------------------------------------------
// Copyright (c) 2026
//-----------------------------------------------------------------------------
// Revisions  :
// Date        Version  Author   Description
// 2026-10-23  1.0      mrosiere Created
//-----------------------------------------------------------------------------

module axi4lite2mem
  #(parameter ADDR_WIDTH = 8                          // Address Width
   ,parameter DATA_WIDTH = 32                         // Data Width
   )
  (
    // Clock & Reset
    input  wire                    clk_i              // Clock
   ,input  wire                    arst_b_i           // Asynchronous Reset active low
    // AXI4-Lite Write Address Channel
   ,input  wire                    s_axi_awvalid_i
   ,output wire                    s_axi_awready_o
   ,input  wire [ADDR_WIDTH-1:0]   s_axi_awaddr_i
    // AXI4-Lite Write Data Channel
   ,input  wire                    s_axi_wvalid_i
   ,output wire                    s_axi_wready_o
   ,input  wire [DATA_WIDTH-1:0]   s_axi_wdata_i
    // verilator lint_off UNUSEDSIGNAL
   ,input  wire [DATA_WIDTH/8-1:0] s_axi_wstrb_i      // Not used
    // verilator lint_on UNUSEDSIGNAL
    // AXI4-Lite Write Response Channel
   ,output wire                    s_axi_bvalid_o
   ,input  wire                    s_axi_bready_i
   ,output wire [1:0]              s_axi_bresp_o
    // AXI4-Lite Read Address Channel
   ,input  wire                    s_axi_arvalid_i
   ,output wire                    s_axi_arready_o
   ,input  wire [ADDR_WIDTH-1:0]   s_axi_araddr_i
    // AXI4-Lite Read Data Channel
   ,output wire                    s_axi_rvalid_o
   ,input  wire                    s_axi_rready_i
   ,output wire [DATA_WIDTH-1:0]   s_axi_rdata_o
   ,output wire [1:0]              s_axi_rresp_o
    // Memory Interface
   ,output wire                    cs_o               // Chip Select
   ,output wire                    re_o               // Read  Enable
   ,output wire                    we_o               // Write Enable
   ,output wire [ADDR_WIDTH-1:0]   addr_o             // Address
   ,output wire [DATA_WIDTH-1:0]   wdata_o            // Write Data
   ,input  wire [DATA_WIDTH-1:0]   rdata_i            // Read  Data
   ,input  wire                    busy_i             // Access not completed
   );

  localparam [1:0] RESP_OKAY = 2'b00;

  localparam [2:0] S_IDLE    = 3'd0;
  localparam [2:0] S_WRITE   = 3'd1;
  localparam [2:0] S_BRESP   = 3'd2;
  localparam [2:0] S_READ    = 3'd3;
  localparam [2:0] S_RRESP   = 3'd4;

  reg  [2:0]            state_r;
  reg  [ADDR_WIDTH-1:0] addr_r;
  reg  [DATA_WIDTH-1:0] wdata_r;
  reg  [DATA_WIDTH-1:0] rdata_r;
  reg                   read_prio_r;                  // 1 : the read wins (last access was a write)

  wire                  write_req;
  wire                  read_req;
  wire                  write_start;
  wire                  read_start;

  // Arbitration
  assign write_req       = s_axi_awvalid_i & s_axi_wvalid_i;
  assign read_req        = s_axi_arvalid_i;

  assign write_start     = (state_r == S_IDLE) & write_req & (~read_req  | ~read_prio_r);
  assign read_start      = (state_r == S_IDLE) & read_req  & (~write_req |  read_prio_r);

  assign s_axi_awready_o = write_start;
  assign s_axi_wready_o  = write_start;
  assign s_axi_arready_o = read_start;

  always @(posedge clk_i or negedge arst_b_i)
    if (!arst_b_i)                      // asynchronous reset (active low)
      begin
        state_r     <= S_IDLE;
        addr_r      <= {ADDR_WIDTH{1'b0}};
        wdata_r     <= {DATA_WIDTH{1'b0}};
        rdata_r     <= {DATA_WIDTH{1'b0}};
        read_prio_r <= 1'b0;
      end
    else
      case (state_r)
        S_IDLE :
          if (write_start)
            begin
              addr_r      <= s_axi_awaddr_i;
              wdata_r     <= s_axi_wdata_i;
              read_prio_r <= 1'b1;
              state_r     <= S_WRITE;
            end
          else if (read_start)
            begin
              addr_r      <= s_axi_araddr_i;
              read_prio_r <= 1'b0;
              state_r     <= S_READ;
            end

        S_WRITE :
          if (!busy_i)
            state_r <= S_BRESP;

        S_BRESP :
          if (s_axi_bready_i)
            state_r <= S_IDLE;

        S_READ :
          if (!busy_i)
            begin
              rdata_r <= rdata_i;
              state_r <= S_RRESP;
            end

        S_RRESP :
          if (s_axi_rready_i)
            state_r <= S_IDLE;

        default :
          state_r <= S_IDLE;
      endcase

  // Memory Interface
  assign cs_o           = (state_r == S_WRITE) | (state_r == S_READ);
  assign we_o           = (state_r == S_WRITE);
  assign re_o           = (state_r == S_READ);
  assign addr_o         = addr_r;
  assign wdata_o        = wdata_r;

  // Responses
  assign s_axi_bvalid_o = (state_r == S_BRESP);
  assign s_axi_bresp_o  = RESP_OKAY;
  assign s_axi_rvalid_o = (state_r == S_RRESP);
  assign s_axi_rdata_o  = rdata_r;
  assign s_axi_rresp_o  = RESP_OKAY;

endmodule
