-------------------------------------------------------------------------------
-- Title      : tb_regtool_apb
-- Project    : regtool
-------------------------------------------------------------------------------
-- File       : tb_regtool_apb.vhd
-- Author     : Mathieu Rosiere
-- Company    :
-- Created    : 2026-10-23
-- Platform   :
-- Standard   : VHDL'08
-------------------------------------------------------------------------------
-- Description:
--  Testbench of the CSR tbcsr generated with the interface "apb" :
--  BFM apb_bfm_pkg -> tbcsr_registers (bridge apb2mem).
--  One scenario per simulation (generic TEST, scenarios of tb_regtool_pkg,
--  chosen at run time), each one from reset. Hardware side : tb_regtool_hw.
-------------------------------------------------------------------------------
-- Copyright (c) 2026
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author   Description
-- 2026-10-23  1.0      mrosiere Created
-- 2026-11-16  2.0      mrosiere UVVM : apb_bfm_pkg, scenarios of tb_regtool_pkg
-------------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;

library uvvm_util;
context uvvm_util.uvvm_util_context;

library asylum;
use     asylum.tbcsr_csr_pkg.all;
use     asylum.tb_regtool_pkg.all;

entity tb_regtool_apb is
  generic (
    TEST            : string := "reset"                    -- Scenario (tb_regtool_pkg)
  );
end entity tb_regtool_apb;

architecture sim of tb_regtool_apb is

  constant C_SCOPE    : string    := "TB_REGTOOL_APB";

  -- Clock and Reset
  signal   clk_i      : std_logic := '0';
  signal   clk_ena    : boolean   := true;
  signal   arst_b_i   : std_logic := '0';

  -- BFM
  signal   bus_if     : t_tb_bus_if;

  -- APB
  signal   psel       : std_logic;
  signal   penable    : std_logic;
  signal   pwrite     : std_logic;
  signal   paddr      : std_logic_vector(TBCSR_ADDR_WIDTH-1 downto 0);
  signal   pwdata     : std_logic_vector(TB_DATA_WIDTH-1 downto 0);
  signal   prdata     : std_logic_vector(TB_DATA_WIDTH-1 downto 0);
  signal   pready     : std_logic;
  signal   pslverr    : std_logic;

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
    ,s_apb_psel_i    => psel
    ,s_apb_penable_i => penable
    ,s_apb_pwrite_i  => pwrite
    ,s_apb_paddr_i   => paddr
    ,s_apb_pwdata_i  => pwdata
    ,s_apb_prdata_o  => prdata
    ,s_apb_pready_o  => pready
    ,s_apb_pslverr_o => pslverr
    ,sw2hw_o         => sw2hw
    ,hw2sw_i         => hw2sw
    );

  -- APB driven by the APB BFM
  psel               <= bus_if.apb.psel;
  penable            <= bus_if.apb.penable;
  pwrite             <= bus_if.apb.pwrite;
  paddr              <= std_logic_vector(bus_if.apb.paddr);
  pwdata             <= bus_if.apb.pwdata;
  bus_if.apb.prdata  <= prdata;
  bus_if.apb.pready  <= pready;
  bus_if.apb.pslverr <= pslverr;

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
    variable v_config : t_tb_bus_config := tb_bus_config(ITF_APB);
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
