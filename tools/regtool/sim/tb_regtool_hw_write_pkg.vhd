-------------------------------------------------------------------------------
-- Title      : tb_regtool_hw_write_pkg
-- Project    : regtool
-------------------------------------------------------------------------------
-- File       : tb_regtool_hw_write_pkg.vhd
-- Author     : Mathieu Rosiere
-- Company    :
-- Created    : 2026-10-23
-- Platform   :
-- Standard   : VHDL'08
-------------------------------------------------------------------------------
-- Description:
--  Scenario hw_write of the regtool testbenches (tb_regtool_<interface>),
--  from reset : register written by the hardware, read only register, rw1c.
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

package tb_regtool_hw_write_pkg is

  -- Register written by the hardware, read only register, rw1c
  procedure run
    (signal   clk      : in    std_logic
    ;signal   bus_if   : inout t_tb_bus_if
    ;constant config   : in    t_tb_bus_config
    ;signal   sw2hw    : in    tbcsr_sw2hw_t
    ;signal   hw_ctrl  : inout t_tb_hw_ctrl
    ;signal   hw_mon   : in    t_tb_hw_mon
    );

end package tb_regtool_hw_write_pkg;

package body tb_regtool_hw_write_pkg is

  procedure run
    (signal   clk      : in    std_logic
    ;signal   bus_if   : inout t_tb_bus_if
    ;constant config   : in    t_tb_bus_config
    ;signal   sw2hw    : in    tbcsr_sw2hw_t
    ;signal   hw_ctrl  : inout t_tb_hw_ctrl
    ;signal   hw_mon   : in    t_tb_hw_mon
    ) is
  begin
    -- Read only register written by the hardware
    hw_ctrl.status       <= (we => '1', busy => "1", count => x"42");
    wait_num_rising_edge(clk, 1);
    hw_ctrl.status.we    <= '0';
    hw_ctrl.status.count <= x"00";
    tb_check(TBCSR_STATUS , x"0000_0421", "status written by the hardware" , clk, bus_if, config);
    -- The software can not write a read only register
    tb_write(TBCSR_STATUS , x"FFFF_FFFF", "status write (read only)"       , clk, bus_if, config);
    tb_check(TBCSR_STATUS , x"0000_0421", "status after a software write"  , clk, bus_if, config);

    -- rw1c : flags set by the hardware, cleared by writing 1
    hw_ctrl.irq          <= (we => '1', flags => "1010");
    wait_num_rising_edge(clk, 1);
    hw_ctrl.irq.we       <= '0';
    tb_check(TBCSR_IRQ    , x"0000_000A", "irq set by the hardware"        , clk, bus_if, config);
    tb_write(TBCSR_IRQ    , x"0000_0002", "irq clear bit 1"                , clk, bus_if, config);
    tb_check(TBCSR_IRQ    , x"0000_0008", "irq after clearing bit 1"       , clk, bus_if, config);
    tb_write(TBCSR_IRQ    , x"0000_0000", "irq write 0"                    , clk, bus_if, config);
    tb_check(TBCSR_IRQ    , x"0000_0008", "irq after writing 0"            , clk, bus_if, config);
    tb_write(TBCSR_IRQ    , x"FFFF_FFFF", "irq clear all"                  , clk, bus_if, config);
    tb_check(TBCSR_IRQ    , x"0000_0000", "irq after clearing all"         , clk, bus_if, config);

    -- A hardware write replaces the value of the register (no OR with it)
    hw_ctrl.irq          <= (we => '1', flags => "0110");
    wait_num_rising_edge(clk, 1);
    hw_ctrl.irq.flags    <= "0011";
    wait_num_rising_edge(clk, 1);
    hw_ctrl.irq.we       <= '0';
    tb_check(TBCSR_IRQ    , x"0000_0003", "irq : the hardware write replaces the value", clk, bus_if, config);
  end procedure run;

end package body tb_regtool_hw_write_pkg;
