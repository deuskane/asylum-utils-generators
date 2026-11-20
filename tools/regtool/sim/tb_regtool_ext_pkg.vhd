-------------------------------------------------------------------------------
-- Title      : tb_regtool_ext_pkg
-- Project    : regtool
-------------------------------------------------------------------------------
-- File       : tb_regtool_ext_pkg.vhd
-- Author     : Mathieu Rosiere
-- Company    :
-- Created    : 2026-10-23
-- Platform   :
-- Standard   : VHDL'08
-------------------------------------------------------------------------------
-- Description:
--  Scenario ext of the regtool testbenches (tb_regtool_<interface>), from
--  reset : external register.
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

package tb_regtool_ext_pkg is

  -- External register
  procedure run
    (signal   clk      : in    std_logic
    ;signal   bus_if   : inout t_tb_bus_if
    ;constant config   : in    t_tb_bus_config
    ;signal   sw2hw    : in    tbcsr_sw2hw_t
    ;signal   hw_ctrl  : inout t_tb_hw_ctrl
    ;signal   hw_mon   : in    t_tb_hw_mon
    );

end package tb_regtool_ext_pkg;

package body tb_regtool_ext_pkg is

  procedure run
    (signal   clk      : in    std_logic
    ;signal   bus_if   : inout t_tb_bus_if
    ;constant config   : in    t_tb_bus_config
    ;signal   sw2hw    : in    tbcsr_sw2hw_t
    ;signal   hw_ctrl  : inout t_tb_hw_ctrl
    ;signal   hw_mon   : in    t_tb_hw_mon
    ) is
  begin
    -- External register : read data from the hardware
    hw_ctrl.ext.data     <= x"1234_5678";
    wait_num_rising_edge(clk, 1);
    tb_check(TBCSR_EXT    , x"1234_5678", "ext read"                       , clk, bus_if, config);
    hw_ctrl.ext.data     <= x"8765_4321";
    wait_num_rising_edge(clk, 1);
    tb_check(TBCSR_EXT    , x"8765_4321", "ext read"                       , clk, bus_if, config);

    -- Write data to the hardware with the write strobe
    tb_write(TBCSR_EXT    , x"DEAD_BEEF", "ext write"                      , clk, bus_if, config);
    wait_num_rising_edge(clk, 1);
    check_value(hw_mon.ext_we_cnt    , 1          , error, "one ext write strobe"        , C_REGTOOL_SCOPE);
    check_value(hw_mon.ext_wdata     , x"DEAD_BEEF", error, "ext data at the write strobe", C_REGTOOL_SCOPE);
  end procedure run;

end package body tb_regtool_ext_pkg;
