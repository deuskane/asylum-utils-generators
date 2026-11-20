-------------------------------------------------------------------------------
-- Title      : tb_regtool_wait_duration_pkg
-- Project    : regtool
-------------------------------------------------------------------------------
-- File       : tb_regtool_wait_duration_pkg.vhd
-- Author     : Mathieu Rosiere
-- Company    :
-- Created    : 2026-10-23
-- Platform   :
-- Standard   : VHDL'08
-------------------------------------------------------------------------------
-- Description:
--  Scenario wait_duration of the regtool testbenches
--  (tb_regtool_<interface>), from reset : duration of the accesses with
--  wait states, back to back accesses.
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

package tb_regtool_wait_duration_pkg is

  -- Duration of the accesses with wait states, back to back accesses
  procedure run
    (signal   clk      : in    std_logic
    ;signal   bus_if   : inout t_tb_bus_if
    ;constant config   : in    t_tb_bus_config
    ;signal   sw2hw    : in    tbcsr_sw2hw_t
    ;signal   hw_ctrl  : inout t_tb_hw_ctrl
    ;signal   hw_mon   : in    t_tb_hw_mon
    );

end package tb_regtool_wait_duration_pkg;

package body tb_regtool_wait_duration_pkg is

  procedure run
    (signal   clk      : in    std_logic
    ;signal   bus_if   : inout t_tb_bus_if
    ;constant config   : in    t_tb_bus_config
    ;signal   sw2hw    : in    tbcsr_sw2hw_t
    ;signal   hw_ctrl  : inout t_tb_hw_ctrl
    ;signal   hw_mon   : in    t_tb_hw_mon
    ) is
    variable v_config : t_tb_bus_config := config;
    variable v_rdata  : std_logic_vector(TB_DATA_WIDTH-1 downto 0);
    variable v_cycles : natural;
    variable v_ref_wr : natural;                             -- Cycles of a write without wait state
    variable v_ref_rd : natural;                             -- Cycles of a read  without wait state
  begin
    -- Duration of an access : the one of a register without wait state
    -- (ctrl) plus the wait states. Accesses back to back (no idle cycle
    -- between two accesses), also to the same register : the shift
    -- register is cleared at the end of each access.
    -- axi4lite : first accesses with the response held by the bridge (BFM
    -- configuration of the testbench ; rcount : the read data of the memory
    -- interface changes every cycle), then bready / rready one cycle after
    -- the address phase, before the response : the access ends at the first
    -- cycle of the response, its duration follows the memory access.
    tb_write(TBCSR_CTRL   , x"0000_0000", "ctrl write, response held"      , clk, bus_if, config);
    tb_read (TBCSR_RCOUNT , v_rdata     , "rcount read, response held"     , clk, bus_if, config);
    v_config.axilite.num_b_pipe_stages := 1;
    v_config.axilite.num_r_pipe_stages := 1;

    tb_write(TBCSR_CTRL   , x"0000_0000", "ctrl write"                     , clk, bus_if, v_config, cycles => v_ref_wr);
    tb_read (TBCSR_CTRL   , v_rdata     , "ctrl read"                      , clk, bus_if, v_config, cycles => v_ref_rd);
    log(ID_SEQUENCER, "Access without wait state : write " & to_string(v_ref_wr) & " cycles, read " & to_string(v_ref_rd) & " cycles", C_REGTOOL_SCOPE);

    for i in 1 to 2 loop
      tb_write(TBCSR_WWAIT  , x"0000_1111", "wwait write"                  , clk, bus_if, v_config, cycles => v_cycles, b2b => true);
      check_value(v_cycles, v_ref_wr + C_WWAIT_WR_WAIT , error, "wwait write : cycles"              , C_REGTOOL_SCOPE);
      tb_read (TBCSR_WWAIT  , v_rdata     , "wwait read"                   , clk, bus_if, v_config, cycles => v_cycles, b2b => true);
      check_value(v_cycles, v_ref_rd                   , error, "wwait read : cycles"               , C_REGTOOL_SCOPE);
      tb_read (TBCSR_RCOUNT , v_rdata     , "rcount read"                  , clk, bus_if, v_config, cycles => v_cycles, b2b => true);
      check_value(v_cycles, v_ref_rd + C_RCOUNT_RD_WAIT, error, "rcount read : cycles"              , C_REGTOOL_SCOPE);
      tb_write(TBCSR_RCOUNT , x"0000_FFFF", "rcount write (read only)"     , clk, bus_if, v_config, cycles => v_cycles, b2b => true);
      check_value(v_cycles, v_ref_wr                   , error, "rcount write (read only) : cycles" , C_REGTOOL_SCOPE);
      tb_write(TBCSR_RCLR   , x"0000_0001", "rclr write"                   , clk, bus_if, v_config, cycles => v_cycles, b2b => true);
      check_value(v_cycles, v_ref_wr + C_RCLR_WR_WAIT  , error, "rclr write : cycles"               , C_REGTOOL_SCOPE);
      tb_write(TBCSR_RCLR   , x"0000_0002", "rclr write"                   , clk, bus_if, v_config, cycles => v_cycles, b2b => true);
      check_value(v_cycles, v_ref_wr + C_RCLR_WR_WAIT  , error, "rclr write : cycles"               , C_REGTOOL_SCOPE);
      tb_read (TBCSR_RCLR   , v_rdata     , "rclr read"                    , clk, bus_if, v_config, cycles => v_cycles, b2b => true);
      check_value(v_cycles, v_ref_rd + C_RCLR_RD_WAIT  , error, "rclr read : cycles"                , C_REGTOOL_SCOPE);
      tb_read (TBCSR_RCLR   , v_rdata     , "rclr read"                    , clk, bus_if, v_config, cycles => v_cycles, b2b => true);
      check_value(v_cycles, v_ref_rd + C_RCLR_RD_WAIT  , error, "rclr read : cycles"                , C_REGTOOL_SCOPE);
    end loop;
  end procedure run;

end package body tb_regtool_wait_duration_pkg;
