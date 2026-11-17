-------------------------------------------------------------------------------
-- Title      : tb_regtool_mem
-- Project    : regtool
-------------------------------------------------------------------------------
-- File       : tb_regtool_mem.vhd
-- Author     : Mathieu Rosiere
-- Company    :
-- Created    : 2026-10-23
-- Platform   :
-- Standard   : VHDL'08
-------------------------------------------------------------------------------
-- Description:
--  Testbench of the CSR tbcsr generated with the interface "mem" :
--  BFM bitvis_vip_sbi -> tbcsr_registers (memory interface : protocol of
--  sbi, access held while busy, ready = not busy).
--  One scenario per simulation (generic TEST, scenarios of tb_regtool_pkg,
--  chosen at run time), each one from reset. Hardware side : tb_regtool_hw.
-------------------------------------------------------------------------------
-- Copyright (c) 2026
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author   Description
-- 2026-10-23  1.0      mrosiere Created
-- 2026-11-16  2.0      mrosiere UVVM : bitvis_vip_sbi, scenarios of tb_regtool_pkg
-------------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;

library uvvm_util;
context uvvm_util.uvvm_util_context;

library bitvis_vip_sbi;
use     bitvis_vip_sbi.sbi_bfm_pkg.all;

library asylum;
use     asylum.tbcsr_csr_pkg.all;
use     asylum.tb_regtool_pkg.all;

entity tb_regtool_mem is
  generic (
    TEST            : string := "reset"                    -- Scenario (tb_regtool_pkg)
  );
end entity tb_regtool_mem;

architecture sim of tb_regtool_mem is

  constant C_SCOPE    : string    := "TB_REGTOOL_MEM";

  -- Clock and Reset
  signal   clk_i      : std_logic := '0';
  signal   clk_ena    : boolean   := true;
  signal   arst_b_i   : std_logic := '0';

  -- BFM
  signal   bus_if     : t_tb_bus_if;

  -- Memory interface
  signal   cs         : std_logic;
  signal   re         : std_logic;
  signal   we         : std_logic;
  signal   addr       : std_logic_vector(TBCSR_ADDR_WIDTH-1 downto 0);
  signal   wdata      : std_logic_vector(TB_DATA_WIDTH-1 downto 0);
  signal   rdata      : std_logic_vector(TB_DATA_WIDTH-1 downto 0);
  signal   busy       : std_logic;

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
    ,cs_i            => cs
    ,re_i            => re
    ,we_i            => we
    ,addr_i          => addr
    ,wdata_i         => wdata
    ,rdata_o         => rdata
    ,busy_o          => busy
    ,sw2hw_o         => sw2hw
    ,hw2sw_i         => hw2sw
    );

  -- Memory interface driven by the SBI BFM
  cs               <= bus_if.sbi.cs;
  re               <= bus_if.sbi.rena;
  we               <= bus_if.sbi.wena;
  addr             <= std_logic_vector(bus_if.sbi.addr(TBCSR_ADDR_WIDTH-1 downto 0));
  wdata            <= bus_if.sbi.wdata;
  bus_if.sbi.ready <= not busy;
  bus_if.sbi.rdata <= rdata;

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
  -- Sequencer
  -----------------------------------------------------------------------------
  p_main : process is
    variable v_config : t_tb_bus_config := tb_bus_config(ITF_MEM);
  begin
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
