-------------------------------------------------------------------------------
-- Title      : tb_regtool_reset_pkg
-- Project    : regtool
-------------------------------------------------------------------------------
-- File       : tb_regtool_reset_pkg.vhd
-- Author     : Mathieu Rosiere
-- Company    :
-- Created    : 2026-10-23
-- Platform   :
-- Standard   : VHDL'08
-------------------------------------------------------------------------------
-- Description:
--  Scenario reset of the regtool testbenches (tb_regtool_<interface>), from
--  reset : reset values on the bus and on the hardware side.
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

package tb_regtool_reset_pkg is

  -- Reset values on the bus and on the hardware side
  procedure run
    (signal   clk      : in    std_logic
    ;signal   bus_if   : inout t_tb_bus_if
    ;constant config   : in    t_tb_bus_config
    ;signal   sw2hw    : in    tbcsr_sw2hw_t
    ;signal   hw_ctrl  : inout t_tb_hw_ctrl
    ;signal   hw_mon   : in    t_tb_hw_mon
    );

end package tb_regtool_reset_pkg;

package body tb_regtool_reset_pkg is

  procedure run
    (signal   clk      : in    std_logic
    ;signal   bus_if   : inout t_tb_bus_if
    ;constant config   : in    t_tb_bus_config
    ;signal   sw2hw    : in    tbcsr_sw2hw_t
    ;signal   hw_ctrl  : inout t_tb_hw_ctrl
    ;signal   hw_mon   : in    t_tb_hw_mon
    ) is
  begin
    -- Bus
    tb_check(TBCSR_CTRL   , x"0000_1021", "ctrl reset value"         , clk, bus_if, config);
    tb_check(TBCSR_STATUS , x"0000_0000", "status reset value"       , clk, bus_if, config);
    tb_check(TBCSR_IRQ    , x"0000_0000", "irq reset value"          , clk, bus_if, config);
    tb_check(TBCSR_CMD    , x"0000_0000", "cmd (write only) read"    , clk, bus_if, config);
    tb_check(TBCSR_EXT    , x"A5A5_0F0F", "ext read (hardware value)", clk, bus_if, config);
    -- Hardware side
    check_value(sw2hw.ctrl.en        , "1"  , error, "sw2hw ctrl.en reset value"  , C_REGTOOL_SCOPE);
    check_value(sw2hw.ctrl.mode      , "10" , error, "sw2hw ctrl.mode reset value", C_REGTOOL_SCOPE);
    check_value(sw2hw.ctrl.div       , x"10", error, "sw2hw ctrl.div reset value" , C_REGTOOL_SCOPE);
    check_value(sw2hw.cmd.op         , x"00", error, "sw2hw cmd.op reset value"   , C_REGTOOL_SCOPE);
    check_value(sw2hw.rx.hw2sw_empty , '1'  , error, "rx FIFO empty after reset"  , C_REGTOOL_SCOPE);
    check_value(sw2hw.tx.sw2hw_empty , '1'  , error, "tx FIFO empty after reset"  , C_REGTOOL_SCOPE);
    check_value(hw_mon.ctrl_we_cnt = 0 and hw_mon.cmd_we_cnt = 0 and hw_mon.ext_we_cnt = 0, error, "no write strobe", C_REGTOOL_SCOPE);
  end procedure run;

end package body tb_regtool_reset_pkg;
