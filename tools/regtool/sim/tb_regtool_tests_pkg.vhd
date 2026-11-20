-------------------------------------------------------------------------------
-- Title      : tb_regtool_tests_pkg
-- Project    : regtool
-------------------------------------------------------------------------------
-- File       : tb_regtool_tests_pkg.vhd
-- Author     : Mathieu Rosiere
-- Company    :
-- Created    : 2026-11-20
-- Platform   :
-- Standard   : VHDL'08
-------------------------------------------------------------------------------
-- Description:
--  Scenarios of the regtool testbenches (tb_regtool_<interface>) : names
--  (valid items of TESTS_LIST) and dispatch (run_test) to the package of
--  each scenario (tb_regtool_<name>_pkg). Each scenario starts from reset :
--  - reset       : reset values (bus and hardware side)
--  - write_read  : software write / read back, write only register
--  - hw_write    : registers written by the hardware, rw1c
--  - ext         : external register
--  - fifo_read   : blocking read of an empty FIFO (bus wait states)
--  - fifo_write  : blocking write of a full FIFO (bus wait states)
--  - unmapped    : access to an unmapped address
--  Wait states of csr_reg (rd_wait_state / wr_wait_state of tbcsr.hjson) :
--  - wait_duration   : duration of the accesses (+ wait states), back to
--                      back accesses
--  - wait_write      : write done once in the first cycle, write strobe
--                      once, during the access
--  - wait_read       : read data of the last cycle, read strobe once
--  - wait_read_clear : read side effect once, after the read data
--  - wait_none       : wait states at 0, same as without them
-------------------------------------------------------------------------------
-- Copyright (c) 2026
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author   Description
-- 2026-11-20  1.0      mrosiere Created (split of tb_regtool_pkg)
-------------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;

library uvvm_util;
context uvvm_util.uvvm_util_context;

library asylum;
use     asylum.string_pkg.all;
use     asylum.tbcsr_csr_pkg.all;
use     asylum.tb_regtool_bfm_pkg.all;

package tb_regtool_tests_pkg is

  -- Names of the scenarios (valid items of TESTS_LIST)
  constant C_TESTS : string := "reset,write_read,hw_write,ext,fifo_read,fifo_write,unmapped,wait_duration,wait_write,wait_read,wait_read_clear,wait_none";

  -- Run the scenario name
  procedure run_test
    (constant name     : in    string
    ;signal   clk      : in    std_logic
    ;signal   bus_if   : inout t_tb_bus_if
    ;constant config   : in    t_tb_bus_config
    ;signal   sw2hw    : in    tbcsr_sw2hw_t
    ;signal   hw_ctrl  : inout t_tb_hw_ctrl
    ;signal   hw_mon   : in    t_tb_hw_mon
    );

end package tb_regtool_tests_pkg;

package body tb_regtool_tests_pkg is

  procedure run_test
    (constant name     : in    string
    ;signal   clk      : in    std_logic
    ;signal   bus_if   : inout t_tb_bus_if
    ;constant config   : in    t_tb_bus_config
    ;signal   sw2hw    : in    tbcsr_sw2hw_t
    ;signal   hw_ctrl  : inout t_tb_hw_ctrl
    ;signal   hw_mon   : in    t_tb_hw_mon
    ) is
  begin
    if    string_eq(name, "reset")
    then
      asylum.tb_regtool_reset_pkg.run(clk, bus_if, config, sw2hw, hw_ctrl, hw_mon);
    elsif string_eq(name, "write_read")
    then
      asylum.tb_regtool_write_read_pkg.run(clk, bus_if, config, sw2hw, hw_ctrl, hw_mon);
    elsif string_eq(name, "hw_write")
    then
      asylum.tb_regtool_hw_write_pkg.run(clk, bus_if, config, sw2hw, hw_ctrl, hw_mon);
    elsif string_eq(name, "ext")
    then
      asylum.tb_regtool_ext_pkg.run(clk, bus_if, config, sw2hw, hw_ctrl, hw_mon);
    elsif string_eq(name, "fifo_read")
    then
      asylum.tb_regtool_fifo_read_pkg.run(clk, bus_if, config, sw2hw, hw_ctrl, hw_mon);
    elsif string_eq(name, "fifo_write")
    then
      asylum.tb_regtool_fifo_write_pkg.run(clk, bus_if, config, sw2hw, hw_ctrl, hw_mon);
    elsif string_eq(name, "unmapped")
    then
      asylum.tb_regtool_unmapped_pkg.run(clk, bus_if, config, sw2hw, hw_ctrl, hw_mon);
    elsif string_eq(name, "wait_duration")
    then
      asylum.tb_regtool_wait_duration_pkg.run(clk, bus_if, config, sw2hw, hw_ctrl, hw_mon);
    elsif string_eq(name, "wait_write")
    then
      asylum.tb_regtool_wait_write_pkg.run(clk, bus_if, config, sw2hw, hw_ctrl, hw_mon);
    elsif string_eq(name, "wait_read")
    then
      asylum.tb_regtool_wait_read_pkg.run(clk, bus_if, config, sw2hw, hw_ctrl, hw_mon);
    elsif string_eq(name, "wait_read_clear")
    then
      asylum.tb_regtool_wait_read_clear_pkg.run(clk, bus_if, config, sw2hw, hw_ctrl, hw_mon);
    elsif string_eq(name, "wait_none")
    then
      asylum.tb_regtool_wait_none_pkg.run(clk, bus_if, config, sw2hw, hw_ctrl, hw_mon);
    else
      alert(TB_ERROR, "Unknown test " & name, C_REGTOOL_SCOPE);
    end if;
  end procedure run_test;

end package body tb_regtool_tests_pkg;
