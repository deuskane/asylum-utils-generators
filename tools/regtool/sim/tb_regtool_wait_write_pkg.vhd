-------------------------------------------------------------------------------
-- Title      : tb_regtool_wait_write_pkg
-- Project    : regtool
-------------------------------------------------------------------------------
-- File       : tb_regtool_wait_write_pkg.vhd
-- Author     : Mathieu Rosiere
-- Company    :
-- Created    : 2026-10-23
-- Platform   :
-- Standard   : VHDL'08
-------------------------------------------------------------------------------
-- Description:
--  Scenario wait_write of the regtool testbenches (tb_regtool_<interface>),
--  from reset : write wait states : written once in the first cycle, write
--  strobe once, during the access.
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

package tb_regtool_wait_write_pkg is

  -- Write wait states : written once in the first cycle, write strobe once, during the access
  procedure run
    (signal   clk      : in    std_logic
    ;signal   bus_if   : inout t_tb_bus_if
    ;constant config   : in    t_tb_bus_config
    ;signal   sw2hw    : in    tbcsr_sw2hw_t
    ;signal   hw_ctrl  : inout t_tb_hw_ctrl
    ;signal   hw_mon   : in    t_tb_hw_mon
    );

end package tb_regtool_wait_write_pkg;

package body tb_regtool_wait_write_pkg is

  procedure run
    (signal   clk      : in    std_logic
    ;signal   bus_if   : inout t_tb_bus_if
    ;constant config   : in    t_tb_bus_config
    ;signal   sw2hw    : in    tbcsr_sw2hw_t
    ;signal   hw_ctrl  : inout t_tb_hw_ctrl
    ;signal   hw_mon   : in    t_tb_hw_mon
    ) is
  begin
    -- wwait (WR_WAIT_STATE = 2) : the register is written once, in the
    -- first cycle of the access, the write strobe pulses once, during the
    -- access. At the strobe, the hardware writes the inverted value : a
    -- software write applied again in a later cycle would replace it.
    tb_write(TBCSR_WWAIT  , x"FFFF_1234", "wwait write"                    , clk, bus_if, config);
    check_value(hw_mon.wwait_we_cnt  , 1      , error, "wwait write strobe during the access"            , C_REGTOOL_SCOPE);
    wait_num_rising_edge(clk, C_WWAIT_WR_WAIT+2);
    check_value(hw_mon.wwait_we_cnt  , 1      , error, "one wwait write strobe"                          , C_REGTOOL_SCOPE);
    check_value(hw_mon.wwait_we_data , x"1234", error, "wwait data at the write strobe"                  , C_REGTOOL_SCOPE);
    check_value(sw2hw.wwait.data     , x"EDCB", error, "wwait written by the hardware during the access" , C_REGTOOL_SCOPE);
    tb_check(TBCSR_WWAIT  , x"0000_EDCB", "wwait read after the write"     , clk, bus_if, config);

    -- Next write : the shift register is back to 0
    tb_write(TBCSR_WWAIT  , x"0000_00FF", "wwait write"                    , clk, bus_if, config);
    check_value(hw_mon.wwait_we_cnt  , 2      , error, "wwait write strobe during the access"            , C_REGTOOL_SCOPE);
    wait_num_rising_edge(clk, C_WWAIT_WR_WAIT+2);
    check_value(hw_mon.wwait_we_cnt  , 2      , error, "one wwait write strobe"                          , C_REGTOOL_SCOPE);
    check_value(hw_mon.wwait_we_data , x"00FF", error, "wwait data at the write strobe"                  , C_REGTOOL_SCOPE);
    tb_check(TBCSR_WWAIT  , x"0000_FF00", "wwait read after the write"     , clk, bus_if, config);
  end procedure run;

end package body tb_regtool_wait_write_pkg;
