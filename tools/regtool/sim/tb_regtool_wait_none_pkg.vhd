-------------------------------------------------------------------------------
-- Title      : tb_regtool_wait_none_pkg
-- Project    : regtool
-------------------------------------------------------------------------------
-- File       : tb_regtool_wait_none_pkg.vhd
-- Author     : Mathieu Rosiere
-- Company    :
-- Created    : 2026-10-23
-- Platform   :
-- Standard   : VHDL'08
-------------------------------------------------------------------------------
-- Description:
--  Scenario wait_none of the regtool testbenches (tb_regtool_<interface>),
--  from reset : wait states at 0 : same duration and strobe timing as
--  without them.
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

package tb_regtool_wait_none_pkg is

  -- Wait states at 0 : same duration and strobe timing as without them
  procedure run
    (signal   clk      : in    std_logic
    ;signal   bus_if   : inout t_tb_bus_if
    ;constant config   : in    t_tb_bus_config
    ;signal   sw2hw    : in    tbcsr_sw2hw_t
    ;signal   hw_ctrl  : inout t_tb_hw_ctrl
    ;signal   hw_mon   : in    t_tb_hw_mon
    );

end package tb_regtool_wait_none_pkg;

package body tb_regtool_wait_none_pkg is

  procedure run
    (signal   clk      : in    std_logic
    ;signal   bus_if   : inout t_tb_bus_if
    ;constant config   : in    t_tb_bus_config
    ;signal   sw2hw    : in    tbcsr_sw2hw_t
    ;signal   hw_ctrl  : inout t_tb_hw_ctrl
    ;signal   hw_mon   : in    t_tb_hw_mon
    ) is
    variable v_rdata  : std_logic_vector(TB_DATA_WIDTH-1 downto 0);
    variable v_cycles : natural;
    variable v_ref_wr : natural;                             -- Cycles of a write without wait state
    variable v_ref_rd : natural;                             -- Cycles of a read  without wait state
    variable v_ref_we : natural;                             -- Write strobes at the end of the write
    variable v_ref_re : natural;                             -- Read  strobes at the end of the read
  begin
    -- nowait (rd_wait_state 0, wr_wait_state "0" : no generic) : same
    -- access duration and same strobe timing as ctrl (no wait state key)
    tb_write(TBCSR_CTRL   , x"0000_0000", "ctrl write"                     , clk, bus_if, config, cycles => v_ref_wr);
    v_ref_we := hw_mon.ctrl_we_cnt;
    tb_read (TBCSR_CTRL   , v_rdata     , "ctrl read"                      , clk, bus_if, config, cycles => v_ref_rd);
    v_ref_re := hw_mon.ctrl_re_cnt;

    tb_write(TBCSR_NOWAIT , x"FFFF_FFA5", "nowait write"                   , clk, bus_if, config, cycles => v_cycles);
    check_value(v_cycles             , v_ref_wr, error, "nowait write : cycles"                    , C_REGTOOL_SCOPE);
    check_value(hw_mon.nowait_we_cnt , v_ref_we, error, "nowait write strobe : same cycle as ctrl" , C_REGTOOL_SCOPE);
    tb_check(TBCSR_NOWAIT , x"0000_00A5", "nowait read back"               , clk, bus_if, config, cycles => v_cycles);
    check_value(v_cycles             , v_ref_rd, error, "nowait read : cycles"                     , C_REGTOOL_SCOPE);
    check_value(hw_mon.nowait_re_cnt , v_ref_re, error, "nowait read strobe : same cycle as ctrl"  , C_REGTOOL_SCOPE);
    wait_num_rising_edge(clk, 2);
    check_value(hw_mon.nowait_we_cnt = 1 and hw_mon.nowait_re_cnt = 1, error, "one nowait strobe per access", C_REGTOOL_SCOPE);
    check_value(sw2hw.nowait.data    , x"A5"   , error, "sw2hw nowait.data"                        , C_REGTOOL_SCOPE);
  end procedure run;

end package body tb_regtool_wait_none_pkg;
