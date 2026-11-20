-------------------------------------------------------------------------------
-- Title      : tb_regtool_wait_read_pkg
-- Project    : regtool
-------------------------------------------------------------------------------
-- File       : tb_regtool_wait_read_pkg.vhd
-- Author     : Mathieu Rosiere
-- Company    :
-- Created    : 2026-10-23
-- Platform   :
-- Standard   : VHDL'08
-------------------------------------------------------------------------------
-- Description:
--  Scenario wait_read of the regtool testbenches (tb_regtool_<interface>),
--  from reset : read wait states : read data of the last cycle, read strobe
--  once, after the access.
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

package tb_regtool_wait_read_pkg is

  -- Read wait states : read data of the last cycle, read strobe once, after the access
  procedure run
    (signal   clk      : in    std_logic
    ;signal   bus_if   : inout t_tb_bus_if
    ;constant config   : in    t_tb_bus_config
    ;signal   sw2hw    : in    tbcsr_sw2hw_t
    ;signal   hw_ctrl  : inout t_tb_hw_ctrl
    ;signal   hw_mon   : in    t_tb_hw_mon
    );

end package tb_regtool_wait_read_pkg;

package body tb_regtool_wait_read_pkg is

  procedure run
    (signal   clk      : in    std_logic
    ;signal   bus_if   : inout t_tb_bus_if
    ;constant config   : in    t_tb_bus_config
    ;signal   sw2hw    : in    tbcsr_sw2hw_t
    ;signal   hw_ctrl  : inout t_tb_hw_ctrl
    ;signal   hw_mon   : in    t_tb_hw_mon
    ) is
    variable v_rdata  : std_logic_vector(TB_DATA_WIDTH-1 downto 0);
  begin
    -- rcount (RD_WAIT_STATE = 2) : the hardware writes the cycle counter
    -- every cycle, also during the access. The read returns the value of
    -- the last cycle of the access (counter of the cycle before), the read
    -- strobe pulses once, the cycle after the access : read data = counter
    -- at the strobe - 2.
    for i in 1 to 3 loop
      tb_read (TBCSR_RCOUNT , v_rdata     , "rcount read"                  , clk, bus_if, config);
      wait_num_rising_edge(clk, C_RCOUNT_RD_WAIT+2);
      check_value(hw_mon.rcount_re_cnt, i, error, "one rcount read strobe per read", C_REGTOOL_SCOPE);
      check_value(v_rdata, x"0000" & std_logic_vector(hw_mon.rcount_re_cyc - 2), error, "rcount read data : value of the last cycle of the access", C_REGTOOL_SCOPE);
    end loop;
  end procedure run;

end package body tb_regtool_wait_read_pkg;
