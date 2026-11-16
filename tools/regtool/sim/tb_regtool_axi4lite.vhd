-------------------------------------------------------------------------------
-- Title      : tb_regtool_axi4lite
-- Project    : regtool
-------------------------------------------------------------------------------
-- File       : tb_regtool_axi4lite.vhd
-- Author     : Mathieu Rosiere
-- Company    :
-- Created    : 2026-10-23
-- Platform   :
-- Standard   : VHDL'08
-------------------------------------------------------------------------------
-- Description:
--  Testbench of the CSR tbcsr generated with the interface "axi4lite" :
--  BFM bitvis_vip_axilite -> tbcsr_registers (bridge axi4lite2mem).
--  BFM : W one cycle after AW, bready / rready 3 cycles after the address
--  phase (the response of an access without wait state is held 2 cycles).
--  Protocol monitor : no awready before wvalid (axi4lite2mem accepts AW and
--  W together), a response is held until it is accepted.
--  One scenario per simulation (generic TEST, scenarios of tb_regtool_pkg,
--  chosen at run time), each one from reset. Hardware side : tb_regtool_hw.
-------------------------------------------------------------------------------
-- Copyright (c) 2026
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author   Description
-- 2026-10-23  1.0      mrosiere Created
-- 2026-11-16  2.0      mrosiere UVVM : bitvis_vip_axilite, AXI protocol monitor, scenarios of tb_regtool_pkg
-------------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;

library uvvm_util;
context uvvm_util.uvvm_util_context;

library bitvis_vip_axilite;
use     bitvis_vip_axilite.axilite_bfm_pkg.all;

library asylum;
use     asylum.tbcsr_csr_pkg.all;
use     asylum.tb_regtool_pkg.all;

entity tb_regtool_axi4lite is
  generic (
    TEST            : string := "reset"                    -- Scenario (tb_regtool_pkg)
  );
end entity tb_regtool_axi4lite;

architecture sim of tb_regtool_axi4lite is

  constant C_SCOPE    : string    := "TB_REGTOOL_AXI4LITE";

  -- Clock and Reset
  signal   clk_i      : std_logic := '0';
  signal   clk_ena    : boolean   := true;
  signal   arst_b_i   : std_logic := '0';

  -- BFM
  signal   bus_if     : t_tb_bus_if;

  -- AXI4-Lite
  signal   awvalid    : std_logic;
  signal   awready    : std_logic;
  signal   awaddr     : std_logic_vector(TBCSR_ADDR_WIDTH-1 downto 0);
  signal   wvalid     : std_logic;
  signal   wready     : std_logic;
  signal   wdata      : std_logic_vector(TB_DATA_WIDTH-1 downto 0);
  signal   wstrb      : std_logic_vector(TB_DATA_WIDTH/8-1 downto 0);
  signal   bvalid     : std_logic;
  signal   bready     : std_logic;
  signal   bresp      : std_logic_vector(2-1 downto 0);
  signal   arvalid    : std_logic;
  signal   arready    : std_logic;
  signal   araddr     : std_logic_vector(TBCSR_ADDR_WIDTH-1 downto 0);
  signal   rvalid     : std_logic;
  signal   rready     : std_logic;
  signal   rdata      : std_logic_vector(TB_DATA_WIDTH-1 downto 0);
  signal   rresp      : std_logic_vector(2-1 downto 0);

  -- Hardware side
  signal   sw2hw      : tbcsr_sw2hw_t;
  signal   hw2sw      : tbcsr_hw2sw_t;
  signal   hw_ctrl    : t_tb_hw_ctrl;
  signal   hw_mon     : t_tb_hw_mon;

begin  -- architecture sim

  -----------------------------------------------------------------------------
  -- Clock and Reset
  -----------------------------------------------------------------------------
  clock_generator(clk_i, clk_ena, C_CLK_PERIOD, "TB Clock");

  arst_b_i <= '0', '1' after 100 ns;

  -----------------------------------------------------------------------------
  -- DUT
  -----------------------------------------------------------------------------
  dut : tbcsr_registers
    port map
    (clk_i           => clk_i
    ,arst_b_i        => arst_b_i
    ,s_axi_awvalid_i => awvalid
    ,s_axi_awready_o => awready
    ,s_axi_awaddr_i  => awaddr
    ,s_axi_wvalid_i  => wvalid
    ,s_axi_wready_o  => wready
    ,s_axi_wdata_i   => wdata
    ,s_axi_wstrb_i   => wstrb
    ,s_axi_bvalid_o  => bvalid
    ,s_axi_bready_i  => bready
    ,s_axi_bresp_o   => bresp
    ,s_axi_arvalid_i => arvalid
    ,s_axi_arready_o => arready
    ,s_axi_araddr_i  => araddr
    ,s_axi_rvalid_o  => rvalid
    ,s_axi_rready_i  => rready
    ,s_axi_rdata_o   => rdata
    ,s_axi_rresp_o   => rresp
    ,sw2hw_o         => sw2hw
    ,hw2sw_i         => hw2sw
    );

  -- AXI4-Lite driven by the AXI-Lite BFM (no awprot / arprot)
  awvalid                                      <= bus_if.axilite.write_address_channel.awvalid;
  awaddr                                       <= bus_if.axilite.write_address_channel.awaddr;
  bus_if.axilite.write_address_channel.awready <= awready;
  wvalid                                       <= bus_if.axilite.write_data_channel.wvalid;
  wdata                                        <= bus_if.axilite.write_data_channel.wdata;
  wstrb                                        <= bus_if.axilite.write_data_channel.wstrb;
  bus_if.axilite.write_data_channel.wready     <= wready;
  bus_if.axilite.write_response_channel.bvalid <= bvalid;
  bus_if.axilite.write_response_channel.bresp  <= bresp;
  bready                                       <= bus_if.axilite.write_response_channel.bready;
  arvalid                                      <= bus_if.axilite.read_address_channel.arvalid;
  araddr                                       <= bus_if.axilite.read_address_channel.araddr;
  bus_if.axilite.read_address_channel.arready  <= arready;
  bus_if.axilite.read_data_channel.rvalid      <= rvalid;
  bus_if.axilite.read_data_channel.rdata       <= rdata;
  bus_if.axilite.read_data_channel.rresp       <= rresp;
  rready                                       <= bus_if.axilite.read_data_channel.rready;

  -----------------------------------------------------------------------------
  -- Hardware side
  -----------------------------------------------------------------------------
  ins_hw : entity work.tb_regtool_hw
    port map
    (clk_i           => clk_i
    ,ctrl_i          => hw_ctrl
    ,mon_o           => hw_mon
    ,sw2hw_i         => sw2hw
    ,hw2sw_o         => hw2sw
    );

  -----------------------------------------------------------------------------
  -- AXI4-Lite protocol monitor (rising edges)
  -----------------------------------------------------------------------------
  p_axi_monitor : process is
    variable v_bvalid : std_logic := '0';                  -- Previous cycle
    variable v_bready : std_logic := '0';
    variable v_bresp  : std_logic_vector(2-1 downto 0);
    variable v_rvalid : std_logic := '0';
    variable v_rready : std_logic := '0';
    variable v_rdata  : std_logic_vector(TB_DATA_WIDTH-1 downto 0);
    variable v_rresp  : std_logic_vector(2-1 downto 0);
  begin
    wait until rising_edge(clk_i);
    -- axi4lite2mem accepts AW and W together
    if awvalid = '1' and wvalid = '0'
    then
      check_value(awready, '0'    , error, "AXI awready before wvalid", C_SCOPE, msg_id => ID_NEVER);
    end if;
    -- A response is held until it is accepted
    if v_bvalid = '1' and v_bready = '0'
    then
      check_value(bvalid , '1'    , error, "AXI bvalid not held"      , C_SCOPE, msg_id => ID_NEVER);
      check_value(bresp  , v_bresp, error, "AXI bresp not held"       , C_SCOPE, msg_id => ID_NEVER);
    end if;
    if v_rvalid = '1' and v_rready = '0'
    then
      check_value(rvalid , '1'    , error, "AXI rvalid not held"      , C_SCOPE, msg_id => ID_NEVER);
      check_value(rdata  , v_rdata, error, "AXI rdata not held"       , C_SCOPE, msg_id => ID_NEVER);
      check_value(rresp  , v_rresp, error, "AXI rresp not held"       , C_SCOPE, msg_id => ID_NEVER);
    end if;
    v_bvalid := bvalid;
    v_bready := bready;
    v_bresp  := bresp;
    v_rvalid := rvalid;
    v_rready := rready;
    v_rdata  := rdata;
    v_rresp  := rresp;
  end process p_axi_monitor;

  -----------------------------------------------------------------------------
  -- Sequencer
  -----------------------------------------------------------------------------
  p_main : process is
    variable v_config : t_tb_bus_config := tb_bus_config(ITF_AXI4LITE);
  begin
    -- W one cycle after AW (the bridge must not accept AW alone), bready /
    -- rready 3 cycles after the address phase : the response of an access
    -- without wait state is held 2 cycles by the bridge before it is accepted
    v_config.axilite.num_aw_pipe_stages := 0;
    v_config.axilite.num_w_pipe_stages  := 1;
    v_config.axilite.num_ar_pipe_stages := 0;
    v_config.axilite.num_b_pipe_stages  := 4;
    v_config.axilite.num_r_pipe_stages  := 4;

    bus_if  <= init_tb_bus_if;
    hw_ctrl <= C_TB_HW_CTRL_INIT;
    wait until arst_b_i = '1';
    wait_num_rising_edge(clk_i, 2);

    run_test(TEST, clk_i, bus_if, v_config, sw2hw, hw_ctrl, hw_mon);

    wait_num_rising_edge(clk_i, 2);
    log(ID_LOG_HDR, "Simulation finished", C_SCOPE);
    report_alert_counters(FINAL);
    std.env.stop;
    wait;
  end process p_main;

end architecture sim;
