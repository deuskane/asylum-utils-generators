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
-------------------------------------------------------------------------------
-- Copyright (c) 2026
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author   Description
-- 2026-10-23  1.0      mrosiere Created
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
  constant ADDR_UNMAPPED : natural := 16#1C#;

  -- Hardware side delay of the FIFO scenarios (a blocking access lasts
  -- more than FIFO_DELAY/2 cycles, an access without wait states less)
  constant FIFO_DELAY    : natural := 20;

  signal   clk           : std_logic := '0';
  signal   arst_b        : std_logic := '0';
  signal   end_of_sim    : boolean   := false;

  -- Monitors of the hardware side
  signal   ctrl_we_cnt   : natural   := 0;
  signal   cmd_we_cnt    : natural   := 0;
  signal   cmd_op        : std_logic_vector(7 downto 0);
  signal   ext_we_cnt    : natural   := 0;
  signal   ext_wdata     : std_logic_vector(31 downto 0);
  signal   rx_push_cnt   : natural   := 0;
  signal   tx_pop_cnt    : natural   := 0;
  signal   tx_pop_data0  : std_logic_vector(15 downto 0);
  signal   tx_pop_data1  : std_logic_vector(15 downto 0);
  signal   fifo_go       : boolean   := false;               -- Second step of the FIFO scenarios

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
    end if;
  end process p_monitor;

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

    -- Software access through the bus master
    procedure sw_access (write : boolean; addr : natural; wdata : std_logic_vector(31 downto 0)) is
    begin
      start  := not start;
      req_o  <= (start => start, write => write,
                 addr  => std_logic_vector(to_unsigned(addr, TB_ADDR_WIDTH)),
                 wdata => wdata);
      wait on rsp_i.done;
      rdata  := rsp_i.rdata;
      cycles := rsp_i.cycles;
    end procedure sw_access;

    procedure sw_write (addr : natural; wdata : std_logic_vector(31 downto 0)) is
    begin
      report "[TESTBENCH] Write 0x" & to_hstring(std_logic_vector(to_unsigned(addr, 8))) & " <= 0x" & to_hstring(wdata);
      sw_access(true, addr, wdata);
    end procedure sw_write;

    procedure sw_read (addr : natural) is
    begin
      sw_access(false, addr, (others => '0'));
      report "[TESTBENCH] Read  0x" & to_hstring(std_logic_vector(to_unsigned(addr, 8))) & " => 0x" & to_hstring(rdata);
    end procedure sw_read;

    procedure sw_check (addr : natural; expected : std_logic_vector(31 downto 0); msg : string) is
    begin
      sw_read(addr);
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
    else
      tb_check(false, "Unknown test " & TEST);
    end if;

    report "[TESTBENCH] Test " & TEST & " OK";
    end_of_sim <= true;
    cycle(2);
    finish;
  end process p_main;

end architecture tb;
