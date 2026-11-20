-------------------------------------------------------------------------------
-- Title      : tb_regtool_hw
-- Project    : regtool
-------------------------------------------------------------------------------
-- File       : tb_regtool_hw.vhd
-- Author     : Mathieu Rosiere
-- Company    :
-- Created    : 2026-10-23
-- Platform   :
-- Standard   : VHDL'08
-------------------------------------------------------------------------------
-- Description:
--  Hardware side of the CSR tbcsr (sim/tbcsr.hjson) in the regtool
--  testbenches, independent of the bus :
--  - status, irq, ext driven by the scenario (ctrl_i)
--  - rx FIFO pushes / tx FIFO pops requested by the scenario (ctrl_i)
--  - wwait : the hardware writes the inverted value at the write strobe
--  - rcount : the hardware writes a cycle counter every cycle
--  - monitors of the strobes and data (mon_o), watchdog of a scenario
--  The reset of a scenario (arst_b_i) clears the monitors and the tx FIFO
--  pop, and restarts the watchdog.
-------------------------------------------------------------------------------
-- Copyright (c) 2026
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author   Description
-- 2026-10-23  1.0      mrosiere Created (tb_regtool_scenario)
-- 2026-11-16  1.1      mrosiere Wait state scenarios, back to back accesses
-- 2026-11-16  2.0      mrosiere UVVM : scenarios moved to tb_regtool_pkg,
--                               hardware side and monitors only
-- 2026-11-20  2.1      mrosiere arst_b_i : reset of the monitors, of the tx
--                               pop and of the watchdog (TESTS_LIST)
-------------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

library uvvm_util;
context uvvm_util.uvvm_util_context;

library asylum;
use     asylum.tbcsr_csr_pkg.all;
use     asylum.tb_regtool_bfm_pkg.all;

entity tb_regtool_hw is
  port (
    -- Clock and Reset
    clk_i         : in  std_logic
   ;arst_b_i      : in  std_logic
    -- Scenario
   ;ctrl_i        : in  t_tb_hw_ctrl
   ;mon_o         : out t_tb_hw_mon
    -- CSR
   ;sw2hw_i       : in  tbcsr_sw2hw_t
   ;hw2sw_o       : out tbcsr_hw2sw_t
  );
end entity tb_regtool_hw;

architecture sim of tb_regtool_hw is

  signal   hw2sw         : tbcsr_hw2sw_t;
  signal   mon           : t_tb_hw_mon           := C_TB_HW_MON_INIT;
  signal   cycle_cnt     : unsigned(16-1 downto 0) := (others => '0'); -- Free running cycle counter

begin  -- architecture sim

  -----------------------------------------------------------------------------
  -- Watchdog : a scenario (from the release of its reset) lasts less than
  -- C_TIMEOUT
  -----------------------------------------------------------------------------
  p_watchdog : process is
  begin
    loop
      wait until arst_b_i = '1';
      wait until arst_b_i = '0' for C_TIMEOUT;
      if arst_b_i = '1'
      then
        alert(TB_FAILURE, "Scenario timeout", C_REGTOOL_SCOPE);
      end if;
    end loop;
  end process p_watchdog;

  -----------------------------------------------------------------------------
  -- Monitors of the hardware side
  -----------------------------------------------------------------------------
  p_monitor : process (clk_i, arst_b_i) is
  begin
    if arst_b_i = '0'
    then
      mon <= C_TB_HW_MON_INIT;
    elsif rising_edge(clk_i)
    then
      if sw2hw_i.ctrl.we = '1'
      then
        mon.ctrl_we_cnt <= mon.ctrl_we_cnt + 1;
      end if;
      if sw2hw_i.ctrl.re = '1'
      then
        mon.ctrl_re_cnt <= mon.ctrl_re_cnt + 1;
      end if;
      if sw2hw_i.cmd.we = '1'
      then
        mon.cmd_we_cnt  <= mon.cmd_we_cnt  + 1;
        mon.cmd_op      <= sw2hw_i.cmd.op;
      end if;
      -- csr_ext : data to the hardware during the software write
      if sw2hw_i.ext.we = '1'
      then
        mon.ext_we_cnt  <= mon.ext_we_cnt  + 1;
        mon.ext_wdata   <= sw2hw_i.ext.data;
      end if;
      if sw2hw_i.rx.ready = '1' and hw2sw.rx.valid = '1'
      then
        mon.rx_push_cnt <= mon.rx_push_cnt + 1;
      end if;
      if sw2hw_i.tx.valid = '1' and hw2sw.tx.ready = '1'
      then
        mon.tx_pop_cnt  <= mon.tx_pop_cnt  + 1;
        if mon.tx_pop_cnt = 0
        then
          mon.tx_pop_data0 <= sw2hw_i.tx.data;
        else
          mon.tx_pop_data1 <= sw2hw_i.tx.data;
        end if;
      end if;
      -- Wait state registers
      if sw2hw_i.wwait.we = '1'
      then
        mon.wwait_we_cnt  <= mon.wwait_we_cnt  + 1;
        mon.wwait_we_data <= sw2hw_i.wwait.data;
      end if;
      if sw2hw_i.rcount.re = '1'
      then
        mon.rcount_re_cnt <= mon.rcount_re_cnt + 1;
        mon.rcount_re_cyc <= cycle_cnt;
      end if;
      if sw2hw_i.rclr.we = '1'
      then
        mon.rclr_we_cnt   <= mon.rclr_we_cnt   + 1;
      end if;
      if sw2hw_i.rclr.re = '1'
      then
        mon.rclr_re_cnt   <= mon.rclr_re_cnt   + 1;
      end if;
      if sw2hw_i.nowait.we = '1'
      then
        mon.nowait_we_cnt <= mon.nowait_we_cnt + 1;
      end if;
      if sw2hw_i.nowait.re = '1'
      then
        mon.nowait_re_cnt <= mon.nowait_re_cnt + 1;
      end if;
    end if;
  end process p_monitor;

  mon_o <= mon;

  -----------------------------------------------------------------------------
  -- Registers written by the scenario
  -----------------------------------------------------------------------------
  hw2sw.status <= ctrl_i.status;
  hw2sw.irq    <= ctrl_i.irq;
  hw2sw.ext    <= ctrl_i.ext;

  -----------------------------------------------------------------------------
  -- Wait state registers
  -----------------------------------------------------------------------------
  -- rcount : the hardware writes the cycle counter every cycle, the register
  -- holds the counter of the previous cycle
  p_cycle : process (clk_i) is
  begin
    if rising_edge(clk_i)
    then
      cycle_cnt <= cycle_cnt + 1;
    end if;
  end process p_cycle;

  hw2sw.rcount.we   <= '1';
  hw2sw.rcount.data <= std_logic_vector(cycle_cnt);

  -- wwait : the hardware writes the inverted value at the write strobe
  hw2sw.wwait.we    <= sw2hw_i.wwait.we;
  hw2sw.wwait.data  <= not sw2hw_i.wwait.data;

  -----------------------------------------------------------------------------
  -- FIFO rx (hardware to software) : on each request, ctrl_i.rx_delay cycles
  -- later, push ctrl_i.rx_data(0 to ctrl_i.rx_nb-1) back to back
  -----------------------------------------------------------------------------
  p_rx : process is

    procedure push (data : std_logic_vector(16-1 downto 0)) is
    begin
      hw2sw.rx.valid <= '1';
      hw2sw.rx.data  <= data;
      loop
        wait until rising_edge(clk_i);
        exit when sw2hw_i.rx.ready = '1';
      end loop;
      hw2sw.rx.valid <= '0';
    end procedure push;

  begin
    hw2sw.rx.valid <= '0';
    hw2sw.rx.data  <= (others => '0');

    loop
      wait on ctrl_i.rx_push;
      for i in 1 to ctrl_i.rx_delay loop
        wait until rising_edge(clk_i);
      end loop;
      for i in 0 to ctrl_i.rx_nb-1 loop
        push(ctrl_i.rx_data(i));
      end loop;
    end loop;
  end process p_rx;

  -----------------------------------------------------------------------------
  -- FIFO tx (software to hardware) : on a request, the hardware pops from
  -- ctrl_i.tx_delay cycles later, until the reset
  -----------------------------------------------------------------------------
  p_tx : process is
  begin
    hw2sw.tx.ready <= '0';

    loop
      wait on ctrl_i.tx_pop, arst_b_i;
      if arst_b_i = '0'
      then
        hw2sw.tx.ready <= '0';
      elsif ctrl_i.tx_pop'event
      then
        for i in 1 to ctrl_i.tx_delay loop
          wait until rising_edge(clk_i);
        end loop;
        hw2sw.tx.ready <= '1';
      end if;
    end loop;
  end process p_tx;

  hw2sw_o <= hw2sw;

end architecture sim;
