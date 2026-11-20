-------------------------------------------------------------------------------
-- Title      : tb_regtool_unmapped_pkg
-- Project    : regtool
-------------------------------------------------------------------------------
-- File       : tb_regtool_unmapped_pkg.vhd
-- Author     : Mathieu Rosiere
-- Company    :
-- Created    : 2026-10-23
-- Platform   :
-- Standard   : VHDL'08
-------------------------------------------------------------------------------
-- Description:
--  Scenario unmapped of the regtool testbenches (tb_regtool_<interface>),
--  from reset : unmapped address : reads 0, write without effect.
-------------------------------------------------------------------------------
-- Copyright (c) 2026
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author   Description
-- 2026-10-23  1.0      mrosiere Created (tb_regtool_scenario)
-- 2026-11-20  2.0      mrosiere One package per scenario (split of
--                               tb_regtool_pkg), procedure run
-------------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

library uvvm_util;
context uvvm_util.uvvm_util_context;

library asylum;
use     asylum.tbcsr_csr_pkg.all;
use     asylum.tb_regtool_bfm_pkg.all;

package tb_regtool_unmapped_pkg is

  -- Unmapped address : reads 0, write without effect
  procedure run
    (signal   clk      : in    std_logic
    ;signal   bus_if   : inout t_tb_bus_if
    ;constant config   : in    t_tb_bus_config
    ;signal   sw2hw    : in    tbcsr_sw2hw_t
    ;signal   hw_ctrl  : inout t_tb_hw_ctrl
    ;signal   hw_mon   : in    t_tb_hw_mon
    );

end package tb_regtool_unmapped_pkg;

package body tb_regtool_unmapped_pkg is

  procedure run
    (signal   clk      : in    std_logic
    ;signal   bus_if   : inout t_tb_bus_if
    ;constant config   : in    t_tb_bus_config
    ;signal   sw2hw    : in    tbcsr_sw2hw_t
    ;signal   hw_ctrl  : inout t_tb_hw_ctrl
    ;signal   hw_mon   : in    t_tb_hw_mon
    ) is
  begin
    -- Unmapped address : read 0, write without effect
    tb_check(C_ADDR_UNMAPPED, x"0000_0000", "unmapped read"                , clk, bus_if, config);
    tb_write(C_ADDR_UNMAPPED, x"FFFF_FFFF", "unmapped write"               , clk, bus_if, config);
    tb_check(TBCSR_CTRL   , x"0000_1021", "ctrl after an unmapped write"   , clk, bus_if, config);
    tb_check(TBCSR_IRQ    , x"0000_0000", "irq after an unmapped write"    , clk, bus_if, config);
    wait_num_rising_edge(clk, 1);
    check_value(hw_mon.ctrl_we_cnt = 0 and hw_mon.cmd_we_cnt = 0 and hw_mon.ext_we_cnt = 0, error, "no write strobe", C_REGTOOL_SCOPE);
  end procedure run;

end package body tb_regtool_unmapped_pkg;
