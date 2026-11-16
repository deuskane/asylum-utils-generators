-------------------------------------------------------------------------------
-- Title      : tb_regtool_scenario
-- Project    : regtool
-------------------------------------------------------------------------------
-- File       : tb_regtool_scenario.vhd
-- Author     : Mathieu Rosiere
-- Company    :
-- Created    : 2026-10-23
-- Platform   :
-- Standard   : VHDL'08
-------------------------------------------------------------------------------
-- Description:
--  Scenarios of the regtool testbenches, independent of the bus : clock,
--  reset, software accesses through the bus master (tb_req_t / tb_rsp_t),
--  hardware side of the CSR tbcsr (sim/tbcsr.hjson).
--  One scenario per simulation (generic TEST), each one starts from reset:
--  - reset       : reset values (bus and hardware side)
--  - write_read  : software write / read back, write only register
--  - hw_write    : registers written by the hardware, rw1c
--  - ext         : external register
--  - fifo_read   : blocking read of an empty FIFO (bus wait states)
--  - fifo_write  : blocking write of a full FIFO (bus wait states)
--  - unmapped    : access to an unmapped address
--  Wait states of csr_reg (rd_wait_state / wr_wait_state of tbcsr.hjson) :
--  - wait_duration   : duration of the accesses (+ wait states), back to
--                      back accesses (mem, sbi, pbi)
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
-- 2026-10-23  1.0      mrosiere Created
-- 2026-11-16  1.1      mrosiere Wait state scenarios, back to back accesses
-------------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

library std;
use     std.env.all;

library asylum;
use     asylum.tbcsr_csr_pkg.all;
use     asylum.tb_regtool_pkg.all;

entity tb_regtool_scenario is
  generic (
    TEST       : string := "reset"
    );
  port (
    clk_o      : out std_logic;
    arst_b_o   : out std_logic;
    req_o      : out tb_req_t;
    rsp_i      : in  tb_rsp_t;
    sw2hw_i    : in  tbcsr_sw2hw_t;
    hw2sw_o    : out tbcsr_hw2sw_t
    );
end entity tb_regtool_scenario;

architecture tb of tb_regtool_scenario is

  -- Addresses
  constant ADDR_CTRL     : natural := to_integer(TBCSR_CTRL  );
  constant ADDR_STATUS   : natural := to_integer(TBCSR_STATUS);
  constant ADDR_IRQ      : natural := to_integer(TBCSR_IRQ   );
  constant ADDR_CMD      : natural := to_integer(TBCSR_CMD   );
  constant ADDR_EXT      : natural := to_integer(TBCSR_EXT   );
  constant ADDR_RX       : natural := to_integer(TBCSR_RX    );
  constant ADDR_TX       : natural := to_integer(TBCSR_TX    );
  constant ADDR_WWAIT    : natural := to_integer(TBCSR_WWAIT );
  constant ADDR_RCOUNT   : natural := to_integer(TBCSR_RCOUNT);
  constant ADDR_RCLR     : natural := to_integer(TBCSR_RCLR  );
  constant ADDR_NOWAIT   : natural := to_integer(TBCSR_NOWAIT);
  constant ADDR_UNMAPPED : natural := 16#1C#;

  -- Wait states of tbcsr.hjson
  constant WWAIT_WR_WAIT : natural := 2;
  constant RCOUNT_RD_WAIT: natural := 2;
  constant RCLR_RD_WAIT  : natural := 2;
  constant RCLR_WR_WAIT  : natural := 1;

  -- Hardware side delay of the FIFO scenarios (a blocking access lasts
  -- more than FIFO_DELAY/2 cycles, an access without wait states less)
  constant FIFO_DELAY    : natural := 20;

  signal   clk           : std_logic := '0';
  signal   arst_b        : std_logic := '0';
  signal   end_of_sim    : boolean   := false;

  -- Monitors of the hardware side
  signal   ctrl_we_cnt   : natural   := 0;
  signal   ctrl_re_cnt   : natural   := 0;
  signal   cmd_we_cnt    : natural   := 0;
  signal   cmd_op        : std_logic_vector(7 downto 0);
  signal   ext_we_cnt    : natural   := 0;
  signal   ext_wdata     : std_logic_vector(31 downto 0);
  signal   rx_push_cnt   : natural   := 0;
  signal   tx_pop_cnt    : natural   := 0;
  signal   tx_pop_data0  : std_logic_vector(15 downto 0);
  signal   tx_pop_data1  : std_logic_vector(15 downto 0);
  signal   fifo_go       : boolean   := false;               -- Second step of the FIFO scenarios

  -- Wait state registers
  signal   cycle_cnt     : unsigned(15 downto 0) := (others => '0'); -- Free running cycle counter
  signal   wwait_we_cnt  : natural   := 0;
  signal   wwait_we_data : std_logic_vector(15 downto 0);
  signal   rcount_re_cnt : natural   := 0;
  signal   rcount_re_cyc : unsigned(15 downto 0);                    -- cycle_cnt at the read strobe
  signal   rclr_we_cnt   : natural   := 0;
  signal   rclr_re_cnt   : natural   := 0;
  signal   nowait_we_cnt : natural   := 0;
  signal   nowait_re_cnt : natural   := 0;

begin  -- architecture tb

  -----------------------------------------------------------------------------
  -- Clock and Reset
  -----------------------------------------------------------------------------
  clk      <= not clk after TB_PERIOD/2;
  arst_b   <= '1' after 5*TB_PERIOD+TB_PERIOD/4;
  clk_o    <= clk;
  arst_b_o <= arst_b;

  -----------------------------------------------------------------------------
  -- Watchdog
  -----------------------------------------------------------------------------
  p_watchdog : process is
  begin
    wait for 100 us;
    tb_check(end_of_sim, "Timeout");
    wait;
  end process p_watchdog;

  -----------------------------------------------------------------------------
  -- Monitors of the hardware side
  -----------------------------------------------------------------------------
  p_monitor : process (clk) is
  begin
    if rising_edge(clk) then
      if sw2hw_i.ctrl.we = '1' then
        ctrl_we_cnt <= ctrl_we_cnt + 1;
      end if;
      if sw2hw_i.ctrl.re = '1' then
        ctrl_re_cnt <= ctrl_re_cnt + 1;
      end if;
      if sw2hw_i.cmd.we = '1' then
        cmd_we_cnt  <= cmd_we_cnt  + 1;
        cmd_op      <= sw2hw_i.cmd.op;
      end if;
      -- csr_ext : data to the hardware during the software write
      if sw2hw_i.ext.we = '1' then
        ext_we_cnt  <= ext_we_cnt  + 1;
        ext_wdata   <= sw2hw_i.ext.data;
      end if;
      if sw2hw_i.rx.ready = '1' and hw2sw_o.rx.valid = '1' then
        rx_push_cnt <= rx_push_cnt + 1;
      end if;
      if sw2hw_i.tx.valid = '1' and hw2sw_o.tx.ready = '1' then
        tx_pop_cnt  <= tx_pop_cnt  + 1;
        if tx_pop_cnt = 0 then
          tx_pop_data0 <= sw2hw_i.tx.data;
        else
          tx_pop_data1 <= sw2hw_i.tx.data;
        end if;
      end if;
      -- Wait state registers
      if sw2hw_i.wwait.we = '1' then
        wwait_we_cnt  <= wwait_we_cnt  + 1;
        wwait_we_data <= sw2hw_i.wwait.data;
      end if;
      if sw2hw_i.rcount.re = '1' then
        rcount_re_cnt <= rcount_re_cnt + 1;
        rcount_re_cyc <= cycle_cnt;
      end if;
      if sw2hw_i.rclr.we = '1' then
        rclr_we_cnt   <= rclr_we_cnt   + 1;
      end if;
      if sw2hw_i.rclr.re = '1' then
        rclr_re_cnt   <= rclr_re_cnt   + 1;
      end if;
      if sw2hw_i.nowait.we = '1' then
        nowait_we_cnt <= nowait_we_cnt + 1;
      end if;
      if sw2hw_i.nowait.re = '1' then
        nowait_re_cnt <= nowait_re_cnt + 1;
      end if;
    end if;
  end process p_monitor;

  -----------------------------------------------------------------------------
  -- Hardware side of the wait state registers
  -----------------------------------------------------------------------------
  -- rcount : the hardware writes the cycle counter every cycle, the register
  -- holds the counter of the previous cycle
  p_cycle : process (clk) is
  begin
    if rising_edge(clk) then
      cycle_cnt <= cycle_cnt + 1;
    end if;
  end process p_cycle;

  hw2sw_o.rcount.we   <= '1';
  hw2sw_o.rcount.data <= std_logic_vector(cycle_cnt);

  -- wwait : the hardware writes the inverted value at the write strobe
  hw2sw_o.wwait.we    <= sw2hw_i.wwait.we;
  hw2sw_o.wwait.data  <= not sw2hw_i.wwait.data;

  -----------------------------------------------------------------------------
  -- Hardware side of the FIFO (rx push, tx pop)
  -----------------------------------------------------------------------------
  p_fifo : process is

    procedure push (data : std_logic_vector(15 downto 0)) is
    begin
      hw2sw_o.rx.valid <= '1';
      hw2sw_o.rx.data  <= data;
      loop
        wait until rising_edge(clk);
        exit when sw2hw_i.rx.ready = '1';
      end loop;
      hw2sw_o.rx.valid <= '0';
    end procedure push;

  begin
    hw2sw_o.rx.valid <= '0';
    hw2sw_o.rx.data  <= (others => '0');
    hw2sw_o.tx.ready <= '0';
    wait until arst_b = '1';

    if TEST = "fifo_read" then
      -- First data FIFO_DELAY cycles after the reset (blocking read)
      for i in 1 to FIFO_DELAY loop
        wait until rising_edge(clk);
      end loop;
      push(x"0077");
      -- Then two data back to back (FIFO full)
      wait until fifo_go;
      push(x"0011");
      push(x"0022");
    end if;

    if TEST = "fifo_write" then
      -- Pop FIFO_DELAY cycles after the second software write is started
      wait until fifo_go;
      for i in 1 to FIFO_DELAY loop
        wait until rising_edge(clk);
      end loop;
      hw2sw_o.tx.ready <= '1';
    end if;

    wait;
  end process p_fifo;

  -----------------------------------------------------------------------------
  -- Scenario
  -----------------------------------------------------------------------------
  p_main : process is
    variable start  : boolean := false;
    variable rdata  : std_logic_vector(31 downto 0);
    variable cycles : natural;
    variable ref_wr : natural;                               -- Cycles of a write without wait state
    variable ref_rd : natural;                               -- Cycles of a read  without wait state
    variable ref_we : natural;                               -- Write strobes at the end of the write
    variable ref_re : natural;                               -- Read  strobes at the end of the read

    -- Software access through the bus master
    -- b2b : back to back with the previous access (call it right after the
    -- previous access, without wait), see tb_req_t
    procedure sw_access (write : boolean; addr : natural; wdata : std_logic_vector(31 downto 0); b2b : boolean := false) is
    begin
      start  := not start;
      req_o  <= (start => start, write => write, b2b => b2b,
                 addr  => std_logic_vector(to_unsigned(addr, TB_ADDR_WIDTH)),
                 wdata => wdata);
      wait on rsp_i.done;
      rdata  := rsp_i.rdata;
      cycles := rsp_i.cycles;
    end procedure sw_access;

    procedure sw_write (addr : natural; wdata : std_logic_vector(31 downto 0); b2b : boolean := false) is
    begin
      report "[TESTBENCH] Write 0x" & to_hstring(std_logic_vector(to_unsigned(addr, 8))) & " <= 0x" & to_hstring(wdata);
      sw_access(true, addr, wdata, b2b);
    end procedure sw_write;

    procedure sw_read (addr : natural; b2b : boolean := false) is
    begin
      sw_access(false, addr, (others => '0'), b2b);
      report "[TESTBENCH] Read  0x" & to_hstring(std_logic_vector(to_unsigned(addr, 8))) & " => 0x" & to_hstring(rdata);
    end procedure sw_read;

    procedure sw_check (addr : natural; expected : std_logic_vector(31 downto 0); msg : string; b2b : boolean := false) is
    begin
      sw_read(addr, b2b);
      tb_check_equal(rdata, expected, msg);
    end procedure sw_check;

    procedure cycle (n : natural := 1) is
    begin
      for i in 1 to n loop
        wait until rising_edge(clk);
      end loop;
    end procedure cycle;

  begin
    req_o                <= TB_REQ_INIT;
    hw2sw_o.status.we    <= '0';
    hw2sw_o.status.busy  <= "0";
    hw2sw_o.status.count <= (others => '0');
    hw2sw_o.irq.we       <= '0';
    hw2sw_o.irq.flags    <= (others => '0');
    hw2sw_o.ext.we       <= '0';
    hw2sw_o.ext.data     <= x"A5A5_0F0F";

    report "[TESTBENCH] Test " & TEST;
    wait until arst_b = '1';
    cycle(2);

    ---------------------------------------------------------------------------
    if    TEST = "reset" then
      -- Bus
      sw_check(ADDR_CTRL    , x"0000_1021", "ctrl reset value");
      sw_check(ADDR_STATUS  , x"0000_0000", "status reset value");
      sw_check(ADDR_IRQ     , x"0000_0000", "irq reset value");
      sw_check(ADDR_CMD     , x"0000_0000", "cmd (write only) read");
      sw_check(ADDR_EXT     , x"A5A5_0F0F", "ext read (hardware value)");
      -- Hardware side
      tb_check_equal(sw2hw_i.ctrl.en  , "1"  , "sw2hw ctrl.en reset value");
      tb_check_equal(sw2hw_i.ctrl.mode, "10" , "sw2hw ctrl.mode reset value");
      tb_check_equal(sw2hw_i.ctrl.div , x"10", "sw2hw ctrl.div reset value");
      tb_check_equal(sw2hw_i.cmd.op   , x"00", "sw2hw cmd.op reset value");
      tb_check(sw2hw_i.rx.hw2sw_empty = '1', "rx FIFO empty after reset");
      tb_check(sw2hw_i.tx.sw2hw_empty = '1', "tx FIFO empty after reset");
      tb_check(ctrl_we_cnt = 0 and cmd_we_cnt = 0 and ext_we_cnt = 0, "no write strobe");

    ---------------------------------------------------------------------------
    elsif TEST = "write_read" then
      -- Read / write register : only the field bits are stored
      sw_write(ADDR_CTRL    , x"FFFF_AB31");
      sw_check(ADDR_CTRL    , x"0000_AB31", "ctrl read back");
      cycle;
      tb_check_equal(sw2hw_i.ctrl.en  , "1"  , "sw2hw ctrl.en");
      tb_check_equal(sw2hw_i.ctrl.mode, "11" , "sw2hw ctrl.mode");
      tb_check_equal(sw2hw_i.ctrl.div , x"AB", "sw2hw ctrl.div");
      tb_check(ctrl_we_cnt = 1, "one ctrl write strobe");

      sw_write(ADDR_CTRL    , x"0000_0000");
      sw_check(ADDR_CTRL    , x"0000_0000", "ctrl read back");

      -- Write only register : the hardware gets the value, the software reads 0
      sw_write(ADDR_CMD     , x"0000_005A");
      sw_check(ADDR_CMD     , x"0000_0000", "cmd (write only) read");
      cycle;
      tb_check(cmd_we_cnt = 1, "one cmd write strobe");
      tb_check_equal(cmd_op          , x"5A", "cmd.op at the write strobe");
      tb_check_equal(sw2hw_i.cmd.op  , x"5A", "sw2hw cmd.op");

    ---------------------------------------------------------------------------
    elsif TEST = "hw_write" then
      -- Read only register written by the hardware
      hw2sw_o.status.we    <= '1';
      hw2sw_o.status.busy  <= "1";
      hw2sw_o.status.count <= x"42";
      cycle;
      hw2sw_o.status.we    <= '0';
      hw2sw_o.status.count <= x"00";
      sw_check(ADDR_STATUS  , x"0000_0421", "status written by the hardware");
      -- The software can not write a read only register
      sw_write(ADDR_STATUS  , x"FFFF_FFFF");
      sw_check(ADDR_STATUS  , x"0000_0421", "status after a software write");

      -- rw1c : flags set by the hardware, cleared by writing 1
      hw2sw_o.irq.we       <= '1';
      hw2sw_o.irq.flags    <= "1010";
      cycle;
      hw2sw_o.irq.we       <= '0';
      sw_check(ADDR_IRQ     , x"0000_000A", "irq set by the hardware");
      sw_write(ADDR_IRQ     , x"0000_0002");
      sw_check(ADDR_IRQ     , x"0000_0008", "irq after clearing bit 1");
      sw_write(ADDR_IRQ     , x"0000_0000");
      sw_check(ADDR_IRQ     , x"0000_0008", "irq after writing 0");
      sw_write(ADDR_IRQ     , x"FFFF_FFFF");
      sw_check(ADDR_IRQ     , x"0000_0000", "irq after clearing all");

    ---------------------------------------------------------------------------
    elsif TEST = "ext" then
      -- External register : read data from the hardware
      hw2sw_o.ext.data <= x"1234_5678";
      cycle;
      sw_check(ADDR_EXT     , x"1234_5678", "ext read");
      hw2sw_o.ext.data <= x"8765_4321";
      cycle;
      sw_check(ADDR_EXT     , x"8765_4321", "ext read");

      -- Write data to the hardware with the write strobe
      sw_write(ADDR_EXT     , x"DEAD_BEEF");
      cycle;
      tb_check(ext_we_cnt = 1, "one ext write strobe");
      tb_check_equal(ext_wdata, x"DEAD_BEEF", "ext data at the write strobe");

    ---------------------------------------------------------------------------
    elsif TEST = "fifo_read" then
      -- Blocking read of the empty FIFO : wait states until the hardware push
      tb_check(sw2hw_i.rx.hw2sw_empty = '1', "rx FIFO empty");
      sw_check(ADDR_RX      , x"0000_0077", "rx first data");
      tb_check(cycles > FIFO_DELAY/2, "rx blocking read : " & integer'image(cycles) & " cycles");
      tb_check(rx_push_cnt = 1, "one rx push");

      -- Two data in the FIFO (depth 2), read in order
      fifo_go <= true;
      if rx_push_cnt /= 3 then
        wait until rx_push_cnt = 3;
      end if;
      cycle;
      tb_check(sw2hw_i.rx.hw2sw_full  = '1', "rx FIFO full");
      sw_check(ADDR_RX      , x"0000_0011", "rx second data");
      sw_check(ADDR_RX      , x"0000_0022", "rx third data");
      cycle;
      tb_check(sw2hw_i.rx.hw2sw_empty = '1', "rx FIFO empty");

    ---------------------------------------------------------------------------
    elsif TEST = "fifo_write" then
      -- First write in the FIFO (depth 1, the hardware does not pop)
      sw_write(ADDR_TX      , x"0000_0101");
      cycle;
      tb_check(sw2hw_i.tx.sw2hw_full = '1', "tx FIFO full");
      tb_check(sw2hw_i.tx.valid      = '1', "tx valid");
      tb_check_equal(sw2hw_i.tx.data, x"0101", "tx data");

      -- Blocking write of the full FIFO : wait states until the hardware pop
      fifo_go <= true;
      sw_write(ADDR_TX      , x"0000_0202");
      tb_check(cycles > FIFO_DELAY/2, "tx blocking write : " & integer'image(cycles) & " cycles");
      -- The second pop can be before the end of the bus access (AXI response)
      if tx_pop_cnt /= 2 then
        wait until tx_pop_cnt = 2;
      end if;
      tb_check_equal(tx_pop_data0, x"0101", "tx first pop");
      tb_check_equal(tx_pop_data1, x"0202", "tx second pop");

    ---------------------------------------------------------------------------
    elsif TEST = "unmapped" then
      -- Unmapped address : read 0, write without effect, no wait state
      sw_check(ADDR_UNMAPPED, x"0000_0000", "unmapped read");
      sw_write(ADDR_UNMAPPED, x"FFFF_FFFF");
      sw_check(ADDR_CTRL    , x"0000_1021", "ctrl after an unmapped write");
      sw_check(ADDR_IRQ     , x"0000_0000", "irq after an unmapped write");
      cycle;
      tb_check(ctrl_we_cnt = 0 and cmd_we_cnt = 0 and ext_we_cnt = 0, "no write strobe");

    ---------------------------------------------------------------------------
    elsif TEST = "wait_duration" then
      -- Duration of an access : the one of a register without wait state
      -- (ctrl) plus the wait states. Accesses back to back (mem, sbi, pbi :
      -- no idle cycle between two accesses), also to the same register :
      -- the shift register is cleared at the end of each access.
      sw_write(ADDR_CTRL    , x"0000_0000");
      ref_wr := cycles;
      sw_read (ADDR_CTRL);
      ref_rd := cycles;
      report "[TESTBENCH] Access without wait state : write " & integer'image(ref_wr) & " cycles, read " & integer'image(ref_rd) & " cycles";

      for i in 1 to 2 loop
        sw_write(ADDR_WWAIT   , x"0000_1111", b2b => true);
        tb_check(cycles = ref_wr + WWAIT_WR_WAIT , "wwait write : "  & integer'image(cycles) & " cycles");
        sw_read (ADDR_WWAIT   , b2b => true);
        tb_check(cycles = ref_rd                 , "wwait read : "   & integer'image(cycles) & " cycles");
        sw_read (ADDR_RCOUNT  , b2b => true);
        tb_check(cycles = ref_rd + RCOUNT_RD_WAIT, "rcount read : "  & integer'image(cycles) & " cycles");
        sw_write(ADDR_RCOUNT  , x"0000_FFFF", b2b => true);
        tb_check(cycles = ref_wr                 , "rcount write (read only) : " & integer'image(cycles) & " cycles");
        sw_write(ADDR_RCLR    , x"0000_0001", b2b => true);
        tb_check(cycles = ref_wr + RCLR_WR_WAIT  , "rclr write : "   & integer'image(cycles) & " cycles");
        sw_write(ADDR_RCLR    , x"0000_0002", b2b => true);
        tb_check(cycles = ref_wr + RCLR_WR_WAIT  , "rclr write : "   & integer'image(cycles) & " cycles");
        sw_read (ADDR_RCLR    , b2b => true);
        tb_check(cycles = ref_rd + RCLR_RD_WAIT  , "rclr read : "    & integer'image(cycles) & " cycles");
        sw_read (ADDR_RCLR    , b2b => true);
        tb_check(cycles = ref_rd + RCLR_RD_WAIT  , "rclr read : "    & integer'image(cycles) & " cycles");
      end loop;

    ---------------------------------------------------------------------------
    elsif TEST = "wait_write" then
      -- wwait (WR_WAIT_STATE = 2) : the register is written once, in the
      -- first cycle of the access, the write strobe pulses once, during the
      -- access. At the strobe, the hardware writes the inverted value : a
      -- software write applied again in a later cycle would replace it.
      sw_write(ADDR_WWAIT   , x"FFFF_1234");
      tb_check(wwait_we_cnt = 1, "wwait write strobe during the access");
      cycle(WWAIT_WR_WAIT+2);
      tb_check(wwait_we_cnt = 1, "one wwait write strobe");
      tb_check_equal(wwait_we_data     , x"1234", "wwait data at the write strobe");
      tb_check_equal(sw2hw_i.wwait.data, x"EDCB", "wwait written by the hardware during the access");
      sw_check(ADDR_WWAIT   , x"0000_EDCB", "wwait read after the write");

      -- Next write : the counter is back to 0
      sw_write(ADDR_WWAIT   , x"0000_00FF");
      tb_check(wwait_we_cnt = 2, "wwait write strobe during the access");
      cycle(WWAIT_WR_WAIT+2);
      tb_check(wwait_we_cnt = 2, "one wwait write strobe");
      tb_check_equal(wwait_we_data     , x"00FF", "wwait data at the write strobe");
      sw_check(ADDR_WWAIT   , x"0000_FF00", "wwait read after the write");

    ---------------------------------------------------------------------------
    elsif TEST = "wait_read" then
      -- rcount (RD_WAIT_STATE = 2) : the hardware writes the cycle counter
      -- every cycle, also during the access. The read returns the value of
      -- the last cycle of the access (counter of the cycle before), the read
      -- strobe pulses once, the cycle after the access : read data = counter
      -- at the strobe - 2.
      for i in 1 to 3 loop
        sw_read (ADDR_RCOUNT);
        cycle(RCOUNT_RD_WAIT+2);
        tb_check(rcount_re_cnt = i, "one rcount read strobe per read");
        tb_check_equal(rdata, x"0000" & std_logic_vector(rcount_re_cyc - 2), "rcount read data : value of the last cycle of the access");
      end loop;

    ---------------------------------------------------------------------------
    elsif TEST = "wait_read_clear" then
      -- rclr (rcw1s, RD_WAIT_STATE = 2, WR_WAIT_STATE = 1) : the read
      -- returns the value before the clear, the clear and the read strobe
      -- are done once, in the last cycle of the access
      sw_write(ADDR_RCLR    , x"FFFF_FF5A");
      cycle(RCLR_WR_WAIT+2);
      tb_check(rclr_we_cnt = 1, "one rclr write strobe");
      tb_check_equal(sw2hw_i.rclr.flags, x"5A", "rclr set by the software write");

      sw_check(ADDR_RCLR    , x"0000_005A", "rclr read : value before the clear");
      cycle(RCLR_RD_WAIT+2);
      tb_check(rclr_re_cnt = 1, "one rclr read strobe");
      tb_check_equal(sw2hw_i.rclr.flags, x"00", "rclr cleared by the read");
      sw_check(ADDR_RCLR    , x"0000_0000", "rclr read after the clear");
      cycle(RCLR_RD_WAIT+2);
      tb_check(rclr_re_cnt = 2, "one rclr read strobe");

      -- Set again, read, cleared : back to back (mem, sbi, pbi)
      sw_write(ADDR_RCLR    , x"0000_0081");
      sw_check(ADDR_RCLR    , x"0000_0081", "rclr read : value before the clear", b2b => true);
      sw_check(ADDR_RCLR    , x"0000_0000", "rclr read after the clear"         , b2b => true);
      cycle(RCLR_RD_WAIT+2);
      tb_check(rclr_we_cnt = 2 and rclr_re_cnt = 4, "one rclr strobe per access");

    ---------------------------------------------------------------------------
    elsif TEST = "wait_none" then
      -- nowait (rd_wait_state 0, wr_wait_state "0" : no generic) : same
      -- access duration and same strobe timing as ctrl (no wait state key)
      sw_write(ADDR_CTRL    , x"0000_0000");
      ref_wr := cycles;
      ref_we := ctrl_we_cnt;
      sw_read (ADDR_CTRL);
      ref_rd := cycles;
      ref_re := ctrl_re_cnt;

      sw_write(ADDR_NOWAIT  , x"FFFF_FFA5");
      tb_check(cycles        = ref_wr, "nowait write : " & integer'image(cycles) & " cycles");
      tb_check(nowait_we_cnt = ref_we, "nowait write strobe : same cycle as ctrl");
      sw_check(ADDR_NOWAIT  , x"0000_00A5", "nowait read back");
      tb_check(cycles        = ref_rd, "nowait read : "  & integer'image(cycles) & " cycles");
      tb_check(nowait_re_cnt = ref_re, "nowait read strobe : same cycle as ctrl");
      cycle(2);
      tb_check(nowait_we_cnt = 1 and nowait_re_cnt = 1, "one nowait strobe per access");
      tb_check_equal(sw2hw_i.nowait.data, x"A5", "sw2hw nowait.data");

    ---------------------------------------------------------------------------
    else
      tb_check(false, "Unknown test " & TEST);
    end if;

    report "[TESTBENCH] Test " & TEST & " OK";
    end_of_sim <= true;
    cycle(2);
    finish;
  end process p_main;

end architecture tb;
