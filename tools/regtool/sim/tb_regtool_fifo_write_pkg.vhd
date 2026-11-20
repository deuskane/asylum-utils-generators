-------------------------------------------------------------------------------
-- Title      : tb_regtool_fifo_write_pkg
-- Project    : regtool
-------------------------------------------------------------------------------
-- File       : tb_regtool_fifo_write_pkg.vhd
-- Author     : Mathieu Rosiere
-- Company    :
-- Created    : 2026-10-23
-- Platform   :
-- Standard   : VHDL'08
-------------------------------------------------------------------------------
-- Description:
--  Scenario fifo_write of the regtool testbenches (tb_regtool_<interface>),
--  from reset : blocking write of a full FIFO, data popped in order.
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

package tb_regtool_fifo_write_pkg is

  -- Blocking write of a full FIFO, data popped in order
  procedure run
    (signal   clk      : in    std_logic
    ;signal   bus_if   : inout t_tb_bus_if
    ;constant config   : in    t_tb_bus_config
    ;signal   sw2hw    : in    tbcsr_sw2hw_t
    ;signal   hw_ctrl  : inout t_tb_hw_ctrl
    ;signal   hw_mon   : in    t_tb_hw_mon
    );

end package tb_regtool_fifo_write_pkg;

package body tb_regtool_fifo_write_pkg is

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
    -- First write in the FIFO (depth 1, the hardware does not pop)
    tb_write(TBCSR_TX     , x"0000_0101", "tx first write"                 , clk, bus_if, config);
    wait_num_rising_edge(clk, 1);
    check_value(sw2hw.tx.sw2hw_full  , '1'    , error, "tx FIFO full", C_REGTOOL_SCOPE);
    check_value(sw2hw.tx.valid       , '1'    , error, "tx valid"    , C_REGTOOL_SCOPE);
    check_value(sw2hw.tx.data        , x"0101", error, "tx data"     , C_REGTOOL_SCOPE);

    -- Blocking write of the full FIFO : wait states until the hardware pop,
    -- C_FIFO_DELAY cycles later
    hw_tx_pop(hw_ctrl, C_FIFO_DELAY);
    tb_write(TBCSR_TX     , x"0000_0202", "tx blocking write"              , clk, bus_if, config, cycles => v_cycles);
    check_value(v_cycles > C_FIFO_DELAY/2, error, "tx blocking write : " & to_string(v_cycles) & " cycles", C_REGTOOL_SCOPE);
    -- The second pop can be before the end of the bus access (AXI response)
    await_value(hw_mon.tx_pop_cnt, 2, 0 ns, 10*C_CLK_PERIOD, error, "tx : two data popped", C_REGTOOL_SCOPE);
    check_value(hw_mon.tx_pop_data0  , x"0101", error, "tx first pop" , C_REGTOOL_SCOPE);
    check_value(hw_mon.tx_pop_data1  , x"0202", error, "tx second pop", C_REGTOOL_SCOPE);
  end procedure run;

end package body tb_regtool_fifo_write_pkg;
