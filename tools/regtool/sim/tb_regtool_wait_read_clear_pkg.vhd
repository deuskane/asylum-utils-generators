-------------------------------------------------------------------------------
-- Title      : tb_regtool_wait_read_clear_pkg
-- Project    : regtool
-------------------------------------------------------------------------------
-- File       : tb_regtool_wait_read_clear_pkg.vhd
-- Author     : Mathieu Rosiere
-- Company    :
-- Created    : 2026-10-23
-- Platform   :
-- Standard   : VHDL'08
-------------------------------------------------------------------------------
-- Description:
--  Scenario wait_read_clear of the regtool testbenches
--  (tb_regtool_<interface>), from reset : read wait states, rcw1s : value
--  before the clear, clear and read strobe once.
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

package tb_regtool_wait_read_clear_pkg is

  -- Read wait states, rcw1s : value before the clear, clear and read strobe once
  procedure run
    (signal   clk      : in    std_logic
    ;signal   bus_if   : inout t_tb_bus_if
    ;constant config   : in    t_tb_bus_config
    ;signal   sw2hw    : in    tbcsr_sw2hw_t
    ;signal   hw_ctrl  : inout t_tb_hw_ctrl
    ;signal   hw_mon   : in    t_tb_hw_mon
    );

end package tb_regtool_wait_read_clear_pkg;

package body tb_regtool_wait_read_clear_pkg is

  procedure run
    (signal   clk      : in    std_logic
    ;signal   bus_if   : inout t_tb_bus_if
    ;constant config   : in    t_tb_bus_config
    ;signal   sw2hw    : in    tbcsr_sw2hw_t
    ;signal   hw_ctrl  : inout t_tb_hw_ctrl
    ;signal   hw_mon   : in    t_tb_hw_mon
    ) is
  begin
    -- rclr (rcw1s, RD_WAIT_STATE = 2, WR_WAIT_STATE = 1) : the read
    -- returns the value before the clear, the clear and the read strobe
    -- are done once, in the last cycle of the access
    tb_write(TBCSR_RCLR   , x"FFFF_FF5A", "rclr write (set)"               , clk, bus_if, config);
    wait_num_rising_edge(clk, C_RCLR_WR_WAIT+2);
    check_value(hw_mon.rclr_we_cnt   , 1    , error, "one rclr write strobe"         , C_REGTOOL_SCOPE);
    check_value(sw2hw.rclr.flags     , x"5A", error, "rclr set by the software write", C_REGTOOL_SCOPE);

    tb_check(TBCSR_RCLR   , x"0000_005A", "rclr read : value before the clear", clk, bus_if, config);
    wait_num_rising_edge(clk, C_RCLR_RD_WAIT+2);
    check_value(hw_mon.rclr_re_cnt   , 1    , error, "one rclr read strobe"          , C_REGTOOL_SCOPE);
    check_value(sw2hw.rclr.flags     , x"00", error, "rclr cleared by the read"      , C_REGTOOL_SCOPE);
    tb_check(TBCSR_RCLR   , x"0000_0000", "rclr read after the clear"      , clk, bus_if, config);
    wait_num_rising_edge(clk, C_RCLR_RD_WAIT+2);
    check_value(hw_mon.rclr_re_cnt   , 2    , error, "one rclr read strobe"          , C_REGTOOL_SCOPE);

    -- Set again, read, cleared : back to back
    tb_write(TBCSR_RCLR   , x"0000_0081", "rclr write (set)"               , clk, bus_if, config);
    tb_check(TBCSR_RCLR   , x"0000_0081", "rclr read : value before the clear", clk, bus_if, config, b2b => true);
    tb_check(TBCSR_RCLR   , x"0000_0000", "rclr read after the clear"      , clk, bus_if, config, b2b => true);
    wait_num_rising_edge(clk, C_RCLR_RD_WAIT+2);
    check_value(hw_mon.rclr_we_cnt = 2 and hw_mon.rclr_re_cnt = 4, error, "one rclr strobe per access", C_REGTOOL_SCOPE);
  end procedure run;

end package body tb_regtool_wait_read_clear_pkg;
