-------------------------------------------------------------------------------
-- Title      : tb_regtool_pkg
-- Project    : regtool
-------------------------------------------------------------------------------
-- File       : tb_regtool_pkg.vhd
-- Author     : Mathieu Rosiere
-- Company    :
-- Created    : 2026-10-23
-- Platform   :
-- Standard   : VHDL'08
-------------------------------------------------------------------------------
-- Description:
--  Scenarios of the regtool testbenches (UVVM), independent of the bus.
--  The CSR tbcsr (sim/tbcsr.hjson) is accessed through the BFM of the
--  interface of the testbench (t_tb_bus_config.itf) :
--  - mem, sbi, pbi : bitvis_vip_sbi (the memory interface and pbi have the
--                    protocol of sbi : access held while busy, ready = not
--                    busy)
--  - apb           : apb_bfm_pkg (UVVM has no APB VIP)
--  - axi4lite      : bitvis_vip_axilite
--  The hardware side of the CSR is tb_regtool_hw : the scenario drives it
--  with t_tb_hw_ctrl and reads its monitors t_tb_hw_mon.
--  One scenario per simulation (generic TEST of the testbench, run_test),
--  each one starts from reset :
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
-- 2026-10-23  1.0      mrosiere Created
-- 2026-11-16  1.1      mrosiere Back to back accesses (tb_req_t.b2b)
-- 2026-11-16  2.0      mrosiere UVVM : scenarios (from tb_regtool_scenario)
--                               as procedures, BFMs instead of the masters
-------------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

library uvvm_util;
context uvvm_util.uvvm_util_context;

library bitvis_vip_sbi;
use     bitvis_vip_sbi.sbi_bfm_pkg.all;

library bitvis_vip_axilite;
use     bitvis_vip_axilite.axilite_bfm_pkg.all;

library asylum;
use     asylum.apb_bfm_pkg.all;
use     asylum.tbcsr_csr_pkg.all;

package tb_regtool_pkg is

  constant C_REGTOOL_SCOPE   : string  := "TB_REGTOOL";  -- Scope of the logs and alerts (C_SCOPE of uvvm_util is hidden by the C_SCOPE of the testbenches)
  constant C_CLK_PERIOD      : time    := 10 ns;
  constant C_TIMEOUT         : time    := 100 us;         -- Watchdog
  constant TB_ADDR_WIDTH     : natural := 8;              -- sbi / pbi address (the bridges take the TBCSR_ADDR_WIDTH LSB)
  constant TB_DATA_WIDTH     : natural := 32;

  -- Hardware side delay of the FIFO scenarios (a blocking access lasts
  -- more than C_FIFO_DELAY/2 cycles, an access without wait states less)
  constant C_FIFO_DELAY      : natural := 20;

  -- Timeout of the BFMs (cycles), longer than a blocking FIFO access
  constant C_MAX_WAIT_CYCLES : natural := 100;

  -- Address without register
  constant C_ADDR_UNMAPPED   : unsigned(TBCSR_ADDR_WIDTH-1 downto 0) := to_unsigned(16#1C#, TBCSR_ADDR_WIDTH);

  -- Wait states of tbcsr.hjson
  constant C_WWAIT_WR_WAIT   : natural := 2;
  constant C_RCOUNT_RD_WAIT  : natural := 2;
  constant C_RCLR_RD_WAIT    : natural := 2;
  constant C_RCLR_WR_WAIT    : natural := 1;

  -----------------------------------------------------------------------------
  -- Bus : interface of the testbench, BFM interfaces and configurations
  -----------------------------------------------------------------------------
  type t_tb_itf is (ITF_MEM, ITF_SBI, ITF_PBI, ITF_APB, ITF_AXI4LITE);

  -- Interfaces of the BFMs : a testbench connects the one of its interface
  -- (sbi : mem, sbi, pbi), the others stay unconnected
  type t_tb_bus_if is record
    sbi            : t_sbi_if    (addr  (TB_ADDR_WIDTH-1 downto 0),
                                  wdata (TB_DATA_WIDTH-1 downto 0),
                                  rdata (TB_DATA_WIDTH-1 downto 0));
    apb            : t_apb_if    (paddr (TBCSR_ADDR_WIDTH-1 downto 0),
                                  pwdata(TB_DATA_WIDTH-1 downto 0),
                                  prdata(TB_DATA_WIDTH-1 downto 0));
    axilite        : t_axilite_if(write_address_channel(awaddr(TBCSR_ADDR_WIDTH-1 downto 0)),
                                  write_data_channel   (wdata (TB_DATA_WIDTH-1 downto 0),
                                                        wstrb (TB_DATA_WIDTH/8-1 downto 0)),
                                  read_address_channel (araddr(TBCSR_ADDR_WIDTH-1 downto 0)),
                                  read_data_channel    (rdata (TB_DATA_WIDTH-1 downto 0)));
  end record t_tb_bus_if;

  -- Interface of the testbench and configuration of the BFMs
  type t_tb_bus_config is record
    itf            : t_tb_itf;
    sbi            : t_sbi_bfm_config;
    apb            : t_apb_bfm_config;
    axilite        : t_axilite_bfm_config;
  end record t_tb_bus_config;

  -- Initial values of the BFM interfaces (inputs at 'Z')
  function init_tb_bus_if return t_tb_bus_if;

  -- Default configuration of the BFMs of the interface itf
  function tb_bus_config(itf : t_tb_itf) return t_tb_bus_config;

  -----------------------------------------------------------------------------
  -- Hardware side (tb_regtool_hw)
  -----------------------------------------------------------------------------
  type t_tb_fifo_data is array (natural range <>) of std_logic_vector(16-1 downto 0);

  -- Driven by the scenario
  type t_tb_hw_ctrl is record
    status         : tbcsr_status_hw2sw_t;                -- Hardware write of status
    irq            : tbcsr_irq_hw2sw_t;                   -- Hardware write of irq
    ext            : tbcsr_ext_hw2sw_t;                   -- Read data of ext
    rx_push        : boolean;                             -- Toggle : push rx_data(0 to rx_nb-1) in the rx FIFO,
    rx_delay       : natural;                             -- back to back, rx_delay cycles later
    rx_nb          : natural;
    rx_data        : t_tb_fifo_data(0 to 1);
    tx_pop         : boolean;                             -- Toggle : pop the tx FIFO from tx_delay cycles later
    tx_delay       : natural;
  end record t_tb_hw_ctrl;

  constant C_TB_HW_CTRL_INIT : t_tb_hw_ctrl := (
    status         => (we => '0', busy  => "0", count => (others => '0')),
    irq            => (we => '0', flags => (others => '0')),
    ext            => (we => '0', data  => x"A5A5_0F0F"),
    rx_push        => false,
    rx_delay       => 0,
    rx_nb          => 0,
    rx_data        => (others => (others => '0')),
    tx_pop         => false,
    tx_delay       => 0
    );

  -- Monitors of the hardware side : strobes counted at the rising edges,
  -- data at the strobe
  type t_tb_hw_mon is record
    ctrl_we_cnt    : natural;
    ctrl_re_cnt    : natural;
    cmd_we_cnt     : natural;
    cmd_op         : std_logic_vector(8-1 downto 0);
    ext_we_cnt     : natural;
    ext_wdata      : std_logic_vector(32-1 downto 0);
    rx_push_cnt    : natural;
    tx_pop_cnt     : natural;
    tx_pop_data0   : std_logic_vector(16-1 downto 0);
    tx_pop_data1   : std_logic_vector(16-1 downto 0);
    wwait_we_cnt   : natural;
    wwait_we_data  : std_logic_vector(16-1 downto 0);
    rcount_re_cnt  : natural;
    rcount_re_cyc  : unsigned(16-1 downto 0);             -- Cycle counter at the read strobe
    rclr_we_cnt    : natural;
    rclr_re_cnt    : natural;
    nowait_we_cnt  : natural;
    nowait_re_cnt  : natural;
  end record t_tb_hw_mon;

  constant C_TB_HW_MON_INIT : t_tb_hw_mon := (
    cmd_op         => (others => 'U'),
    ext_wdata      => (others => 'U'),
    tx_pop_data0   => (others => 'U'),
    tx_pop_data1   => (others => 'U'),
    wwait_we_data  => (others => 'U'),
    rcount_re_cyc  => (others => 'U'),
    others         => 0
    );

  -----------------------------------------------------------------------------
  -- Software accesses through the BFM of config.itf
  -- b2b    : back to back, the access starts in the cycle that follows the
  --          previous access (call right after the previous access, without
  --          wait) ; otherwise the bus is idle at one rising edge before the
  --          access.
  -- cycles : duration of the access, rising edges from the first one where
  --          the access is on the bus to the one where it completes.
  -----------------------------------------------------------------------------
  procedure tb_write(
    constant addr_value : in    unsigned;
    constant data_value : in    std_logic_vector;
    constant msg        : in    string;
    signal   clk        : in    std_logic;
    signal   bus_if     : inout t_tb_bus_if;
    constant config     : in    t_tb_bus_config;
    variable cycles     : out   natural;
    constant b2b        : in    boolean := false);

  procedure tb_write(
    constant addr_value : in    unsigned;
    constant data_value : in    std_logic_vector;
    constant msg        : in    string;
    signal   clk        : in    std_logic;
    signal   bus_if     : inout t_tb_bus_if;
    constant config     : in    t_tb_bus_config;
    constant b2b        : in    boolean := false);

  procedure tb_read(
    constant addr_value : in    unsigned;
    variable data_value : out   std_logic_vector;
    constant msg        : in    string;
    signal   clk        : in    std_logic;
    signal   bus_if     : inout t_tb_bus_if;
    constant config     : in    t_tb_bus_config;
    variable cycles     : out   natural;
    constant b2b        : in    boolean := false);

  procedure tb_read(
    constant addr_value : in    unsigned;
    variable data_value : out   std_logic_vector;
    constant msg        : in    string;
    signal   clk        : in    std_logic;
    signal   bus_if     : inout t_tb_bus_if;
    constant config     : in    t_tb_bus_config;
    constant b2b        : in    boolean := false);

  -- Read and check the read data
  procedure tb_check(
    constant addr_value : in    unsigned;
    constant data_exp   : in    std_logic_vector;
    constant msg        : in    string;
    signal   clk        : in    std_logic;
    signal   bus_if     : inout t_tb_bus_if;
    constant config     : in    t_tb_bus_config;
    variable cycles     : out   natural;
    constant b2b        : in    boolean := false);

  procedure tb_check(
    constant addr_value : in    unsigned;
    constant data_exp   : in    std_logic_vector;
    constant msg        : in    string;
    signal   clk        : in    std_logic;
    signal   bus_if     : inout t_tb_bus_if;
    constant config     : in    t_tb_bus_config;
    constant b2b        : in    boolean := false);

  -----------------------------------------------------------------------------
  -- Scenarios (parameters : clock, BFM interfaces and configuration,
  -- hardware side)
  -----------------------------------------------------------------------------
  -- Call the scenario named test (generic TEST of the testbench)
  procedure run_test(
    constant test       : in    string;
    signal   clk        : in    std_logic;
    signal   bus_if     : inout t_tb_bus_if;
    constant config     : in    t_tb_bus_config;
    signal   sw2hw      : in    tbcsr_sw2hw_t;
    signal   hw_ctrl    : inout t_tb_hw_ctrl;
    signal   hw_mon     : in    t_tb_hw_mon);

  -- Reset values on the bus and on the hardware side
  procedure test_reset          (signal clk : in std_logic; signal bus_if : inout t_tb_bus_if; constant config : in t_tb_bus_config;
                                 signal sw2hw : in tbcsr_sw2hw_t; signal hw_ctrl : inout t_tb_hw_ctrl; signal hw_mon : in t_tb_hw_mon);
  -- Software write / read back (only the field bits), write strobe, write only register
  procedure test_write_read     (signal clk : in std_logic; signal bus_if : inout t_tb_bus_if; constant config : in t_tb_bus_config;
                                 signal sw2hw : in tbcsr_sw2hw_t; signal hw_ctrl : inout t_tb_hw_ctrl; signal hw_mon : in t_tb_hw_mon);
  -- Register written by the hardware, read only register, rw1c
  procedure test_hw_write       (signal clk : in std_logic; signal bus_if : inout t_tb_bus_if; constant config : in t_tb_bus_config;
                                 signal sw2hw : in tbcsr_sw2hw_t; signal hw_ctrl : inout t_tb_hw_ctrl; signal hw_mon : in t_tb_hw_mon);
  -- External register
  procedure test_ext            (signal clk : in std_logic; signal bus_if : inout t_tb_bus_if; constant config : in t_tb_bus_config;
                                 signal sw2hw : in tbcsr_sw2hw_t; signal hw_ctrl : inout t_tb_hw_ctrl; signal hw_mon : in t_tb_hw_mon);
  -- Blocking read of an empty FIFO, FIFO order, full / empty flags
  procedure test_fifo_read      (signal clk : in std_logic; signal bus_if : inout t_tb_bus_if; constant config : in t_tb_bus_config;
                                 signal sw2hw : in tbcsr_sw2hw_t; signal hw_ctrl : inout t_tb_hw_ctrl; signal hw_mon : in t_tb_hw_mon);
  -- Blocking write of a full FIFO, data popped in order
  procedure test_fifo_write     (signal clk : in std_logic; signal bus_if : inout t_tb_bus_if; constant config : in t_tb_bus_config;
                                 signal sw2hw : in tbcsr_sw2hw_t; signal hw_ctrl : inout t_tb_hw_ctrl; signal hw_mon : in t_tb_hw_mon);
  -- Unmapped address : reads 0, write without effect
  procedure test_unmapped       (signal clk : in std_logic; signal bus_if : inout t_tb_bus_if; constant config : in t_tb_bus_config;
                                 signal sw2hw : in tbcsr_sw2hw_t; signal hw_ctrl : inout t_tb_hw_ctrl; signal hw_mon : in t_tb_hw_mon);
  -- Duration of the accesses with wait states, back to back accesses
  procedure test_wait_duration  (signal clk : in std_logic; signal bus_if : inout t_tb_bus_if; constant config : in t_tb_bus_config;
                                 signal sw2hw : in tbcsr_sw2hw_t; signal hw_ctrl : inout t_tb_hw_ctrl; signal hw_mon : in t_tb_hw_mon);
  -- Write wait states : written once in the first cycle, write strobe once, during the access
  procedure test_wait_write     (signal clk : in std_logic; signal bus_if : inout t_tb_bus_if; constant config : in t_tb_bus_config;
                                 signal sw2hw : in tbcsr_sw2hw_t; signal hw_ctrl : inout t_tb_hw_ctrl; signal hw_mon : in t_tb_hw_mon);
  -- Read wait states : read data of the last cycle, read strobe once, after the access
  procedure test_wait_read      (signal clk : in std_logic; signal bus_if : inout t_tb_bus_if; constant config : in t_tb_bus_config;
                                 signal sw2hw : in tbcsr_sw2hw_t; signal hw_ctrl : inout t_tb_hw_ctrl; signal hw_mon : in t_tb_hw_mon);
  -- Read wait states, rcw1s : value before the clear, clear and read strobe once
  procedure test_wait_read_clear(signal clk : in std_logic; signal bus_if : inout t_tb_bus_if; constant config : in t_tb_bus_config;
                                 signal sw2hw : in tbcsr_sw2hw_t; signal hw_ctrl : inout t_tb_hw_ctrl; signal hw_mon : in t_tb_hw_mon);
  -- Wait states at 0 : same duration and strobe timing as without them
  procedure test_wait_none      (signal clk : in std_logic; signal bus_if : inout t_tb_bus_if; constant config : in t_tb_bus_config;
                                 signal sw2hw : in tbcsr_sw2hw_t; signal hw_ctrl : inout t_tb_hw_ctrl; signal hw_mon : in t_tb_hw_mon);

end package tb_regtool_pkg;

package body tb_regtool_pkg is

  -----------------------------------------------------------------------------
  -- Bus
  -----------------------------------------------------------------------------
  function init_tb_bus_if return t_tb_bus_if is
    variable v_if : t_tb_bus_if;
  begin
    v_if.sbi     := init_sbi_if_signals    (TB_ADDR_WIDTH   , TB_DATA_WIDTH);
    v_if.apb     := init_apb_if_signals    (TBCSR_ADDR_WIDTH, TB_DATA_WIDTH);
    v_if.axilite := init_axilite_if_signals(TBCSR_ADDR_WIDTH, TB_DATA_WIDTH);
    return v_if;
  end function init_tb_bus_if;

  function tb_bus_config(itf : t_tb_itf) return t_tb_bus_config is
    variable v_config : t_tb_bus_config;
  begin
    v_config.itf                                := itf;
    v_config.sbi                                := C_SBI_BFM_CONFIG_DEFAULT;
    v_config.sbi.max_wait_cycles                := C_MAX_WAIT_CYCLES;
    v_config.sbi.max_wait_cycles_severity       := error;
    v_config.apb                                := C_APB_BFM_CONFIG_DEFAULT;
    v_config.apb.max_wait_cycles                := C_MAX_WAIT_CYCLES;
    v_config.apb.max_wait_cycles_severity       := error;
    v_config.axilite                            := C_AXILITE_BFM_CONFIG_DEFAULT;
    v_config.axilite.max_wait_cycles            := C_MAX_WAIT_CYCLES;
    v_config.axilite.max_wait_cycles_severity   := error;
    v_config.axilite.expected_response_severity := error;
    return v_config;
  end function tb_bus_config;

  -- Start of an access, returns the rising edge before its first cycle
  procedure tb_access_start(
    constant msg        : in    string;
    signal   clk        : in    std_logic;
    constant b2b        : in    boolean;
    variable edge       : out   time) is
  begin
    if b2b
    then
      -- A BFM returns a quarter of a period after the rising edge that
      -- ends its access : the next access is on the bus at the next one
      check_value(clk = '1' and clk'last_event > 0 ns and clk'last_event < C_CLK_PERIOD/2, TB_ERROR,
                  "back to back access right after the previous one : " & msg, C_REGTOOL_SCOPE, ID_NEVER);
    else
      -- Idle cycle
      wait until rising_edge(clk);
    end if;
    edge := now - clk'last_event;
  end procedure tb_access_start;

  -- Duration of an access that started after the rising edge edge, at the
  -- return of the BFM (a quarter of a period after the last rising edge)
  impure function tb_access_cycles(
    signal   clk        : in    std_logic;
    constant edge       : in    time) return natural is
  begin
    return (now - clk'last_event - edge) / C_CLK_PERIOD;
  end function tb_access_cycles;

  procedure tb_write(
    constant addr_value : in    unsigned;
    constant data_value : in    std_logic_vector;
    constant msg        : in    string;
    signal   clk        : in    std_logic;
    signal   bus_if     : inout t_tb_bus_if;
    constant config     : in    t_tb_bus_config;
    variable cycles     : out   natural;
    constant b2b        : in    boolean := false) is
    variable v_edge     : time;
  begin
    tb_access_start(msg, clk, b2b, v_edge);
    case config.itf is
      when ITF_APB      => apb_write    (addr_value => addr_value, data_value => data_value, msg => msg, clk => clk, apb_if     => bus_if.apb    , config => config.apb    );
      when ITF_AXI4LITE => axilite_write(addr_value => addr_value, data_value => data_value, msg => msg, clk => clk, axilite_if => bus_if.axilite, config => config.axilite);
      when others       => sbi_write    (addr_value => addr_value, data_value => data_value, msg => msg, clk => clk, sbi_if     => bus_if.sbi    , config => config.sbi    );
    end case;
    cycles := tb_access_cycles(clk, v_edge);
  end procedure tb_write;

  procedure tb_write(
    constant addr_value : in    unsigned;
    constant data_value : in    std_logic_vector;
    constant msg        : in    string;
    signal   clk        : in    std_logic;
    signal   bus_if     : inout t_tb_bus_if;
    constant config     : in    t_tb_bus_config;
    constant b2b        : in    boolean := false) is
    variable v_cycles   : natural;
  begin
    tb_write(addr_value, data_value, msg, clk, bus_if, config, v_cycles, b2b);
  end procedure tb_write;

  procedure tb_read(
    constant addr_value : in    unsigned;
    variable data_value : out   std_logic_vector;
    constant msg        : in    string;
    signal   clk        : in    std_logic;
    signal   bus_if     : inout t_tb_bus_if;
    constant config     : in    t_tb_bus_config;
    variable cycles     : out   natural;
    constant b2b        : in    boolean := false) is
    variable v_edge     : time;
  begin
    tb_access_start(msg, clk, b2b, v_edge);
    case config.itf is
      when ITF_APB      => apb_read     (addr_value => addr_value, data_value => data_value, msg => msg, clk => clk, apb_if     => bus_if.apb    , config => config.apb    );
      when ITF_AXI4LITE => axilite_read (addr_value => addr_value, data_value => data_value, msg => msg, clk => clk, axilite_if => bus_if.axilite, config => config.axilite);
      when others       => sbi_read     (addr_value => addr_value, data_value => data_value, msg => msg, clk => clk, sbi_if     => bus_if.sbi    , config => config.sbi    );
    end case;
    cycles := tb_access_cycles(clk, v_edge);
  end procedure tb_read;

  procedure tb_read(
    constant addr_value : in    unsigned;
    variable data_value : out   std_logic_vector;
    constant msg        : in    string;
    signal   clk        : in    std_logic;
    signal   bus_if     : inout t_tb_bus_if;
    constant config     : in    t_tb_bus_config;
    constant b2b        : in    boolean := false) is
    variable v_cycles   : natural;
  begin
    tb_read(addr_value, data_value, msg, clk, bus_if, config, v_cycles, b2b);
  end procedure tb_read;

  procedure tb_check(
    constant addr_value : in    unsigned;
    constant data_exp   : in    std_logic_vector;
    constant msg        : in    string;
    signal   clk        : in    std_logic;
    signal   bus_if     : inout t_tb_bus_if;
    constant config     : in    t_tb_bus_config;
    variable cycles     : out   natural;
    constant b2b        : in    boolean := false) is
    variable v_edge     : time;
  begin
    tb_access_start(msg, clk, b2b, v_edge);
    case config.itf is
      when ITF_APB      => apb_check    (addr_value => addr_value, data_exp => data_exp, msg => msg, clk => clk, apb_if     => bus_if.apb    , alert_level => error, config => config.apb    );
      when ITF_AXI4LITE => axilite_check(addr_value => addr_value, data_exp => data_exp, msg => msg, clk => clk, axilite_if => bus_if.axilite, alert_level => error, config => config.axilite);
      when others       => sbi_check    (addr_value => addr_value, data_exp => data_exp, msg => msg, clk => clk, sbi_if     => bus_if.sbi    , alert_level => error, config => config.sbi    );
    end case;
    cycles := tb_access_cycles(clk, v_edge);
  end procedure tb_check;

  procedure tb_check(
    constant addr_value : in    unsigned;
    constant data_exp   : in    std_logic_vector;
    constant msg        : in    string;
    signal   clk        : in    std_logic;
    signal   bus_if     : inout t_tb_bus_if;
    constant config     : in    t_tb_bus_config;
    constant b2b        : in    boolean := false) is
    variable v_cycles   : natural;
  begin
    tb_check(addr_value, data_exp, msg, clk, bus_if, config, v_cycles, b2b);
  end procedure tb_check;

  -----------------------------------------------------------------------------
  -- Hardware side
  -----------------------------------------------------------------------------
  -- Push data in the rx FIFO, back to back, delay cycles later
  procedure hw_rx_push(
    signal   hw_ctrl    : inout t_tb_hw_ctrl;
    constant data       : in    t_tb_fifo_data;
    constant delay      : in    natural) is
  begin
    hw_ctrl.rx_data(0 to data'length-1) <= data;
    hw_ctrl.rx_nb                       <= data'length;
    hw_ctrl.rx_delay                    <= delay;
    hw_ctrl.rx_push                     <= not hw_ctrl.rx_push;
  end procedure hw_rx_push;

  -- Pop the tx FIFO from delay cycles later
  procedure hw_tx_pop(
    signal   hw_ctrl    : inout t_tb_hw_ctrl;
    constant delay      : in    natural) is
  begin
    hw_ctrl.tx_delay                    <= delay;
    hw_ctrl.tx_pop                      <= not hw_ctrl.tx_pop;
  end procedure hw_tx_pop;

  -----------------------------------------------------------------------------
  -- Scenarios
  -----------------------------------------------------------------------------
  procedure run_test(
    constant test       : in    string;
    signal   clk        : in    std_logic;
    signal   bus_if     : inout t_tb_bus_if;
    constant config     : in    t_tb_bus_config;
    signal   sw2hw      : in    tbcsr_sw2hw_t;
    signal   hw_ctrl    : inout t_tb_hw_ctrl;
    signal   hw_mon     : in    t_tb_hw_mon) is
  begin
    log(ID_LOG_HDR, "Test " & test & " (" & t_tb_itf'image(config.itf) & ")", C_REGTOOL_SCOPE);

    if    test = "reset"           then test_reset          (clk, bus_if, config, sw2hw, hw_ctrl, hw_mon);
    elsif test = "write_read"      then test_write_read     (clk, bus_if, config, sw2hw, hw_ctrl, hw_mon);
    elsif test = "hw_write"        then test_hw_write       (clk, bus_if, config, sw2hw, hw_ctrl, hw_mon);
    elsif test = "ext"             then test_ext            (clk, bus_if, config, sw2hw, hw_ctrl, hw_mon);
    elsif test = "fifo_read"       then test_fifo_read      (clk, bus_if, config, sw2hw, hw_ctrl, hw_mon);
    elsif test = "fifo_write"      then test_fifo_write     (clk, bus_if, config, sw2hw, hw_ctrl, hw_mon);
    elsif test = "unmapped"        then test_unmapped       (clk, bus_if, config, sw2hw, hw_ctrl, hw_mon);
    elsif test = "wait_duration"   then test_wait_duration  (clk, bus_if, config, sw2hw, hw_ctrl, hw_mon);
    elsif test = "wait_write"      then test_wait_write     (clk, bus_if, config, sw2hw, hw_ctrl, hw_mon);
    elsif test = "wait_read"       then test_wait_read      (clk, bus_if, config, sw2hw, hw_ctrl, hw_mon);
    elsif test = "wait_read_clear" then test_wait_read_clear(clk, bus_if, config, sw2hw, hw_ctrl, hw_mon);
    elsif test = "wait_none"       then test_wait_none      (clk, bus_if, config, sw2hw, hw_ctrl, hw_mon);
    else
      alert(TB_ERROR, "Unknown TEST """ & test & """", C_REGTOOL_SCOPE);
    end if;
  end procedure run_test;

  -----------------------------------------------------------------------------
  procedure test_reset          (signal clk : in std_logic; signal bus_if : inout t_tb_bus_if; constant config : in t_tb_bus_config;
                                 signal sw2hw : in tbcsr_sw2hw_t; signal hw_ctrl : inout t_tb_hw_ctrl; signal hw_mon : in t_tb_hw_mon) is
  begin
    -- Bus
    tb_check(TBCSR_CTRL   , x"0000_1021", "ctrl reset value"         , clk, bus_if, config);
    tb_check(TBCSR_STATUS , x"0000_0000", "status reset value"       , clk, bus_if, config);
    tb_check(TBCSR_IRQ    , x"0000_0000", "irq reset value"          , clk, bus_if, config);
    tb_check(TBCSR_CMD    , x"0000_0000", "cmd (write only) read"    , clk, bus_if, config);
    tb_check(TBCSR_EXT    , x"A5A5_0F0F", "ext read (hardware value)", clk, bus_if, config);
    -- Hardware side
    check_value(sw2hw.ctrl.en        , "1"  , error, "sw2hw ctrl.en reset value"  , C_REGTOOL_SCOPE);
    check_value(sw2hw.ctrl.mode      , "10" , error, "sw2hw ctrl.mode reset value", C_REGTOOL_SCOPE);
    check_value(sw2hw.ctrl.div       , x"10", error, "sw2hw ctrl.div reset value" , C_REGTOOL_SCOPE);
    check_value(sw2hw.cmd.op         , x"00", error, "sw2hw cmd.op reset value"   , C_REGTOOL_SCOPE);
    check_value(sw2hw.rx.hw2sw_empty , '1'  , error, "rx FIFO empty after reset"  , C_REGTOOL_SCOPE);
    check_value(sw2hw.tx.sw2hw_empty , '1'  , error, "tx FIFO empty after reset"  , C_REGTOOL_SCOPE);
    check_value(hw_mon.ctrl_we_cnt = 0 and hw_mon.cmd_we_cnt = 0 and hw_mon.ext_we_cnt = 0, error, "no write strobe", C_REGTOOL_SCOPE);
  end procedure test_reset;

  -----------------------------------------------------------------------------
  procedure test_write_read     (signal clk : in std_logic; signal bus_if : inout t_tb_bus_if; constant config : in t_tb_bus_config;
                                 signal sw2hw : in tbcsr_sw2hw_t; signal hw_ctrl : inout t_tb_hw_ctrl; signal hw_mon : in t_tb_hw_mon) is
  begin
    -- Read / write register : only the field bits are stored
    tb_write(TBCSR_CTRL   , x"FFFF_AB31", "ctrl write"               , clk, bus_if, config);
    tb_check(TBCSR_CTRL   , x"0000_AB31", "ctrl read back"           , clk, bus_if, config);
    wait_num_rising_edge(clk, 1);
    check_value(sw2hw.ctrl.en        , "1"  , error, "sw2hw ctrl.en"              , C_REGTOOL_SCOPE);
    check_value(sw2hw.ctrl.mode      , "11" , error, "sw2hw ctrl.mode"            , C_REGTOOL_SCOPE);
    check_value(sw2hw.ctrl.div       , x"AB", error, "sw2hw ctrl.div"             , C_REGTOOL_SCOPE);
    check_value(hw_mon.ctrl_we_cnt   , 1    , error, "one ctrl write strobe"      , C_REGTOOL_SCOPE);

    tb_write(TBCSR_CTRL   , x"0000_0000", "ctrl write"               , clk, bus_if, config);
    tb_check(TBCSR_CTRL   , x"0000_0000", "ctrl read back"           , clk, bus_if, config);

    -- Write only register : the hardware gets the value, the software reads 0
    tb_write(TBCSR_CMD    , x"0000_005A", "cmd write"                , clk, bus_if, config);
    tb_check(TBCSR_CMD    , x"0000_0000", "cmd (write only) read"    , clk, bus_if, config);
    wait_num_rising_edge(clk, 1);
    check_value(hw_mon.cmd_we_cnt    , 1    , error, "one cmd write strobe"       , C_REGTOOL_SCOPE);
    check_value(hw_mon.cmd_op        , x"5A", error, "cmd.op at the write strobe" , C_REGTOOL_SCOPE);
    check_value(sw2hw.cmd.op         , x"5A", error, "sw2hw cmd.op"               , C_REGTOOL_SCOPE);
  end procedure test_write_read;

  -----------------------------------------------------------------------------
  procedure test_hw_write       (signal clk : in std_logic; signal bus_if : inout t_tb_bus_if; constant config : in t_tb_bus_config;
                                 signal sw2hw : in tbcsr_sw2hw_t; signal hw_ctrl : inout t_tb_hw_ctrl; signal hw_mon : in t_tb_hw_mon) is
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
  end procedure test_hw_write;

  -----------------------------------------------------------------------------
  procedure test_ext            (signal clk : in std_logic; signal bus_if : inout t_tb_bus_if; constant config : in t_tb_bus_config;
                                 signal sw2hw : in tbcsr_sw2hw_t; signal hw_ctrl : inout t_tb_hw_ctrl; signal hw_mon : in t_tb_hw_mon) is
  begin
    -- External register : read data from the hardware
    hw_ctrl.ext.data     <= x"1234_5678";
    wait_num_rising_edge(clk, 1);
    tb_check(TBCSR_EXT    , x"1234_5678", "ext read"                       , clk, bus_if, config);
    hw_ctrl.ext.data     <= x"8765_4321";
    wait_num_rising_edge(clk, 1);
    tb_check(TBCSR_EXT    , x"8765_4321", "ext read"                       , clk, bus_if, config);

    -- Write data to the hardware with the write strobe
    tb_write(TBCSR_EXT    , x"DEAD_BEEF", "ext write"                      , clk, bus_if, config);
    wait_num_rising_edge(clk, 1);
    check_value(hw_mon.ext_we_cnt    , 1          , error, "one ext write strobe"        , C_REGTOOL_SCOPE);
    check_value(hw_mon.ext_wdata     , x"DEAD_BEEF", error, "ext data at the write strobe", C_REGTOOL_SCOPE);
  end procedure test_ext;

  -----------------------------------------------------------------------------
  procedure test_fifo_read      (signal clk : in std_logic; signal bus_if : inout t_tb_bus_if; constant config : in t_tb_bus_config;
                                 signal sw2hw : in tbcsr_sw2hw_t; signal hw_ctrl : inout t_tb_hw_ctrl; signal hw_mon : in t_tb_hw_mon) is
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
  end procedure test_fifo_read;

  -----------------------------------------------------------------------------
  procedure test_fifo_write     (signal clk : in std_logic; signal bus_if : inout t_tb_bus_if; constant config : in t_tb_bus_config;
                                 signal sw2hw : in tbcsr_sw2hw_t; signal hw_ctrl : inout t_tb_hw_ctrl; signal hw_mon : in t_tb_hw_mon) is
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
  end procedure test_fifo_write;

  -----------------------------------------------------------------------------
  procedure test_unmapped       (signal clk : in std_logic; signal bus_if : inout t_tb_bus_if; constant config : in t_tb_bus_config;
                                 signal sw2hw : in tbcsr_sw2hw_t; signal hw_ctrl : inout t_tb_hw_ctrl; signal hw_mon : in t_tb_hw_mon) is
  begin
    -- Unmapped address : read 0, write without effect
    tb_check(C_ADDR_UNMAPPED, x"0000_0000", "unmapped read"                , clk, bus_if, config);
    tb_write(C_ADDR_UNMAPPED, x"FFFF_FFFF", "unmapped write"               , clk, bus_if, config);
    tb_check(TBCSR_CTRL   , x"0000_1021", "ctrl after an unmapped write"   , clk, bus_if, config);
    tb_check(TBCSR_IRQ    , x"0000_0000", "irq after an unmapped write"    , clk, bus_if, config);
    wait_num_rising_edge(clk, 1);
    check_value(hw_mon.ctrl_we_cnt = 0 and hw_mon.cmd_we_cnt = 0 and hw_mon.ext_we_cnt = 0, error, "no write strobe", C_REGTOOL_SCOPE);
  end procedure test_unmapped;

  -----------------------------------------------------------------------------
  procedure test_wait_duration  (signal clk : in std_logic; signal bus_if : inout t_tb_bus_if; constant config : in t_tb_bus_config;
                                 signal sw2hw : in tbcsr_sw2hw_t; signal hw_ctrl : inout t_tb_hw_ctrl; signal hw_mon : in t_tb_hw_mon) is
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
  end procedure test_wait_duration;

  -----------------------------------------------------------------------------
  procedure test_wait_write     (signal clk : in std_logic; signal bus_if : inout t_tb_bus_if; constant config : in t_tb_bus_config;
                                 signal sw2hw : in tbcsr_sw2hw_t; signal hw_ctrl : inout t_tb_hw_ctrl; signal hw_mon : in t_tb_hw_mon) is
  begin
    -- wwait (WR_WAIT_STATE = 2) : the register is written once, in the
    -- first cycle of the access, the write strobe pulses once, during the
    -- access. At the strobe, the hardware writes the inverted value : a
    -- software write applied again in a later cycle would replace it.
    tb_write(TBCSR_WWAIT  , x"FFFF_1234", "wwait write"                    , clk, bus_if, config);
    check_value(hw_mon.wwait_we_cnt  , 1      , error, "wwait write strobe during the access"            , C_REGTOOL_SCOPE);
    wait_num_rising_edge(clk, C_WWAIT_WR_WAIT+2);
    check_value(hw_mon.wwait_we_cnt  , 1      , error, "one wwait write strobe"                          , C_REGTOOL_SCOPE);
    check_value(hw_mon.wwait_we_data , x"1234", error, "wwait data at the write strobe"                  , C_REGTOOL_SCOPE);
    check_value(sw2hw.wwait.data     , x"EDCB", error, "wwait written by the hardware during the access" , C_REGTOOL_SCOPE);
    tb_check(TBCSR_WWAIT  , x"0000_EDCB", "wwait read after the write"     , clk, bus_if, config);

    -- Next write : the shift register is back to 0
    tb_write(TBCSR_WWAIT  , x"0000_00FF", "wwait write"                    , clk, bus_if, config);
    check_value(hw_mon.wwait_we_cnt  , 2      , error, "wwait write strobe during the access"            , C_REGTOOL_SCOPE);
    wait_num_rising_edge(clk, C_WWAIT_WR_WAIT+2);
    check_value(hw_mon.wwait_we_cnt  , 2      , error, "one wwait write strobe"                          , C_REGTOOL_SCOPE);
    check_value(hw_mon.wwait_we_data , x"00FF", error, "wwait data at the write strobe"                  , C_REGTOOL_SCOPE);
    tb_check(TBCSR_WWAIT  , x"0000_FF00", "wwait read after the write"     , clk, bus_if, config);
  end procedure test_wait_write;

  -----------------------------------------------------------------------------
  procedure test_wait_read      (signal clk : in std_logic; signal bus_if : inout t_tb_bus_if; constant config : in t_tb_bus_config;
                                 signal sw2hw : in tbcsr_sw2hw_t; signal hw_ctrl : inout t_tb_hw_ctrl; signal hw_mon : in t_tb_hw_mon) is
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
  end procedure test_wait_read;

  -----------------------------------------------------------------------------
  procedure test_wait_read_clear(signal clk : in std_logic; signal bus_if : inout t_tb_bus_if; constant config : in t_tb_bus_config;
                                 signal sw2hw : in tbcsr_sw2hw_t; signal hw_ctrl : inout t_tb_hw_ctrl; signal hw_mon : in t_tb_hw_mon) is
  begin
    -- rclr (rcw1s, RD_WAIT_STATE = 2, WR_WAIT_STATE = 1) : the read
    -- returns the value before the clear, the clear and the read strobe
    -- are done once, in the last cycle of the access
    tb_write(TBCSR_RCLR   , x"FFFF_FF5A", "rclr write (set)"               , clk, bus_if, config);
    wait_num_rising_edge(clk, C_RCLR_WR_WAIT+2);
    check_value(hw_mon.rclr_we_cnt   , 1    , error, "one rclr write strobe"         , C_REGTOOL_SCOPE);
    check_value(sw2hw.rclr.flags     , x"5A", error, "rclr set by the software write", C_REGTOOL_SCOPE);

    tb_check(TBCSR_RCLR   , x"0000_005A", "rclr read : value before the clear", clk, bus_if, config);
    wait_num_rising_edge(clk, C_RCLR_RD_WAIT+2);
    check_value(hw_mon.rclr_re_cnt   , 1    , error, "one rclr read strobe"          , C_REGTOOL_SCOPE);
    check_value(sw2hw.rclr.flags     , x"00", error, "rclr cleared by the read"      , C_REGTOOL_SCOPE);
    tb_check(TBCSR_RCLR   , x"0000_0000", "rclr read after the clear"      , clk, bus_if, config);
    wait_num_rising_edge(clk, C_RCLR_RD_WAIT+2);
    check_value(hw_mon.rclr_re_cnt   , 2    , error, "one rclr read strobe"          , C_REGTOOL_SCOPE);

    -- Set again, read, cleared : back to back
    tb_write(TBCSR_RCLR   , x"0000_0081", "rclr write (set)"               , clk, bus_if, config);
    tb_check(TBCSR_RCLR   , x"0000_0081", "rclr read : value before the clear", clk, bus_if, config, b2b => true);
    tb_check(TBCSR_RCLR   , x"0000_0000", "rclr read after the clear"      , clk, bus_if, config, b2b => true);
    wait_num_rising_edge(clk, C_RCLR_RD_WAIT+2);
    check_value(hw_mon.rclr_we_cnt = 2 and hw_mon.rclr_re_cnt = 4, error, "one rclr strobe per access", C_REGTOOL_SCOPE);
  end procedure test_wait_read_clear;

  -----------------------------------------------------------------------------
  procedure test_wait_none      (signal clk : in std_logic; signal bus_if : inout t_tb_bus_if; constant config : in t_tb_bus_config;
                                 signal sw2hw : in tbcsr_sw2hw_t; signal hw_ctrl : inout t_tb_hw_ctrl; signal hw_mon : in t_tb_hw_mon) is
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
  end procedure test_wait_none;

end package body tb_regtool_pkg;
