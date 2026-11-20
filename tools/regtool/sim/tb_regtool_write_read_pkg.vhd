-------------------------------------------------------------------------------
-- Title      : tb_regtool_write_read_pkg
-- Project    : regtool
-------------------------------------------------------------------------------
-- File       : tb_regtool_write_read_pkg.vhd
-- Author     : Mathieu Rosiere
-- Company    :
-- Created    : 2026-10-23
-- Platform   :
-- Standard   : VHDL'08
-------------------------------------------------------------------------------
-- Description:
--  Scenario write_read of the regtool testbenches (tb_regtool_<interface>),
--  from reset : software write / read back (only the field bits), write
--  strobe, write only register.
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

package tb_regtool_write_read_pkg is

  -- Software write / read back (only the field bits), write strobe, write only register
  procedure run
    (signal   clk      : in    std_logic
    ;signal   bus_if   : inout t_tb_bus_if
    ;constant config   : in    t_tb_bus_config
    ;signal   sw2hw    : in    tbcsr_sw2hw_t
    ;signal   hw_ctrl  : inout t_tb_hw_ctrl
    ;signal   hw_mon   : in    t_tb_hw_mon
    );

end package tb_regtool_write_read_pkg;

package body tb_regtool_write_read_pkg is

  procedure run
    (signal   clk      : in    std_logic
    ;signal   bus_if   : inout t_tb_bus_if
    ;constant config   : in    t_tb_bus_config
    ;signal   sw2hw    : in    tbcsr_sw2hw_t
    ;signal   hw_ctrl  : inout t_tb_hw_ctrl
    ;signal   hw_mon   : in    t_tb_hw_mon
    ) is
  begin
    -- Read / write register : only the field bits are stored
    tb_write(TBCSR_CTRL   , x"FFFF_AB31", "ctrl write"               , clk, bus_if, config);
    tb_check(TBCSR_CTRL   , x"0000_AB31", "ctrl read back"           , clk, bus_if, config);
    wait_num_rising_edge(clk, 1);
    check_value(sw2hw.ctrl.en        , "1"  , error, "sw2hw ctrl.en"              , C_REGTOOL_SCOPE);
    check_value(sw2hw.ctrl.mode      , "11" , error, "sw2hw ctrl.mode"            , C_REGTOOL_SCOPE);
    check_value(sw2hw.ctrl.div       , x"AB", error, "sw2hw ctrl.div"             , C_REGTOOL_SCOPE);
    check_value(hw_mon.ctrl_we_cnt   , 1    , error, "one ctrl write strobe"      , C_REGTOOL_SCOPE);

    tb_write(TBCSR_CTRL   , x"0000_0000", "ctrl write"               , clk, bus_if, config);
    tb_check(TBCSR_CTRL   , x"0000_0000", "ctrl read back"           , clk, bus_if, config);

    -- Write only register : the hardware gets the value, the software reads 0
    tb_write(TBCSR_CMD    , x"0000_005A", "cmd write"                , clk, bus_if, config);
    tb_check(TBCSR_CMD    , x"0000_0000", "cmd (write only) read"    , clk, bus_if, config);
    wait_num_rising_edge(clk, 1);
    check_value(hw_mon.cmd_we_cnt    , 1    , error, "one cmd write strobe"       , C_REGTOOL_SCOPE);
    check_value(hw_mon.cmd_op        , x"5A", error, "cmd.op at the write strobe" , C_REGTOOL_SCOPE);
    check_value(sw2hw.cmd.op         , x"5A", error, "sw2hw cmd.op"               , C_REGTOOL_SCOPE);
  end procedure run;

end package body tb_regtool_write_read_pkg;
