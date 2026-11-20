-------------------------------------------------------------------------------
-- Title      : tb_regtool_fifo_read_pkg
-- Project    : regtool
-------------------------------------------------------------------------------
-- File       : tb_regtool_fifo_read_pkg.vhd
-- Author     : Mathieu Rosiere
-- Company    :
-- Created    : 2026-10-23
-- Platform   :
-- Standard   : VHDL'08
-------------------------------------------------------------------------------
-- Description:
--  Scenario fifo_read of the regtool testbenches (tb_regtool_<interface>),
--  from reset : blocking read of an empty FIFO, FIFO order, full / empty
--  flags.
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

package tb_regtool_fifo_read_pkg is

  -- Blocking read of an empty FIFO, FIFO order, full / empty flags
  procedure run
    (signal   clk      : in    std_logic
    ;signal   bus_if   : inout t_tb_bus_if
    ;constant config   : in    t_tb_bus_config
    ;signal   sw2hw    : in    tbcsr_sw2hw_t
    ;signal   hw_ctrl  : inout t_tb_hw_ctrl
    ;signal   hw_mon   : in    t_tb_hw_mon
    );

end package tb_regtool_fifo_read_pkg;

package body tb_regtool_fifo_read_pkg is

  procedure run
    (signal   clk      : in    std_logic
    ;signal   bus_if   : inout t_tb_bus_if
    ;constant config   : in    t_tb_bus_config
    ;signal   sw2hw    : in    tbcsr_sw2hw_t
    ;signal   hw_ctrl  : inout t_tb_hw_ctrl
    ;signal   hw_mon   : in    t_tb_hw_mon
    ) is
    variable v_cycles : natural;
  begin
    -- Blocking read of the empty FIFO : wait states until the hardware push,
    -- C_FIFO_DELAY cycles later
    check_value(sw2hw.rx.hw2sw_empty , '1', error, "rx FIFO empty", C_REGTOOL_SCOPE);
    hw_rx_push(hw_ctrl, (0 => x"0077"), C_FIFO_DELAY);
    tb_check(TBCSR_RX     , x"0000_0077", "rx first data"                  , clk, bus_if, config, cycles => v_cycles);
    check_value(v_cycles > C_FIFO_DELAY/2, error, "rx blocking read : " & to_string(v_cycles) & " cycles", C_REGTOOL_SCOPE);
    check_value(hw_mon.rx_push_cnt   , 1  , error, "one rx push"  , C_REGTOOL_SCOPE);

    -- Two data in the FIFO (depth 2), read in order
    hw_rx_push(hw_ctrl, (x"0011", x"0022"), 0);
    await_value(hw_mon.rx_push_cnt, 3, 0 ns, 10*C_CLK_PERIOD, error, "rx : two data pushed", C_REGTOOL_SCOPE);
    wait_num_rising_edge(clk, 1);
    check_value(sw2hw.rx.hw2sw_full  , '1', error, "rx FIFO full" , C_REGTOOL_SCOPE);
    tb_check(TBCSR_RX     , x"0000_0011", "rx second data"                 , clk, bus_if, config);
    tb_check(TBCSR_RX     , x"0000_0022", "rx third data"                  , clk, bus_if, config);
    wait_num_rising_edge(clk, 1);
    check_value(sw2hw.rx.hw2sw_empty , '1', error, "rx FIFO empty", C_REGTOOL_SCOPE);
  end procedure run;

end package body tb_regtool_fifo_read_pkg;
