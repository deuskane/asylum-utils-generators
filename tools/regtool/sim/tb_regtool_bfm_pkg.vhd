-------------------------------------------------------------------------------
-- Title      : tb_regtool_bfm_pkg
-- Project    : regtool
-------------------------------------------------------------------------------
-- File       : tb_regtool_bfm_pkg.vhd
-- Author     : Mathieu Rosiere
-- Company    :
-- Created    : 2026-10-23
-- Platform   :
-- Standard   : VHDL'08
-------------------------------------------------------------------------------
-- Description:
--  Helpers shared by the scenarios of the regtool testbenches (UVVM),
--  independent of the bus. The CSR tbcsr (sim/tbcsr.hjson) is accessed
--  through the BFM of the interface of the testbench (t_tb_bus_config.itf) :
--  - mem, sbi, pbi : bitvis_vip_sbi (the memory interface and pbi have the
--                    protocol of sbi : access held while busy, ready = not
--                    busy)
--  - apb           : apb_bfm_pkg (UVVM has no APB VIP)
--  - axi4lite      : bitvis_vip_axilite
--  The hardware side of the CSR is tb_regtool_hw : the scenario drives it
--  with t_tb_hw_ctrl and reads its monitors t_tb_hw_mon.
--  Reset pulse of the sequencer (do_reset) and hardware side back to idle
--  (hw_init) before each scenario.
-------------------------------------------------------------------------------
-- Copyright (c) 2026
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author   Description
-- 2026-10-23  1.0      mrosiere Created
-- 2026-11-16  1.1      mrosiere Back to back accesses (tb_req_t.b2b)
-- 2026-11-16  2.0      mrosiere UVVM : scenarios (from tb_regtool_scenario)
--                               as procedures, BFMs instead of the masters
-- 2026-11-20  3.0      mrosiere Was tb_regtool_pkg : helpers only (one
--                               package per scenario), do_reset, hw_init
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

package tb_regtool_bfm_pkg is

  constant C_REGTOOL_SCOPE   : string  := "TB_REGTOOL";  -- Scope of the logs and alerts (C_SCOPE of uvvm_util is hidden by the C_SCOPE of the testbenches)
  constant C_CLK_PERIOD      : time    := 10 ns;
  constant C_TIMEOUT         : time    := 100 us;         -- Watchdog of a scenario
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
  -- Hardware side
  -----------------------------------------------------------------------------
  -- Push data in the rx FIFO, back to back, delay cycles later
  procedure hw_rx_push(
    signal   hw_ctrl    : inout t_tb_hw_ctrl;
    constant data       : in    t_tb_fifo_data;
    constant delay      : in    natural);

  -- Pop the tx FIFO from delay cycles later
  procedure hw_tx_pop(
    signal   hw_ctrl    : inout t_tb_hw_ctrl;
    constant delay      : in    natural);

  -- Hardware side back to idle (before the reset of a scenario) : values
  -- written by the hardware and FIFO parameters at their initial value ; the
  -- requests rx_push / tx_pop are toggles, left unchanged (a change would be
  -- a request)
  procedure hw_init(
    signal   hw_ctrl    : inout t_tb_hw_ctrl);

  -----------------------------------------------------------------------------
  -- Sequencer
  -----------------------------------------------------------------------------
  -- Reset pulse, released on the falling edge of the clock
  procedure do_reset(
    signal   clk        : in    std_logic;
    signal   arst_b     : out   std_logic);

end package tb_regtool_bfm_pkg;

package body tb_regtool_bfm_pkg is

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

  procedure hw_init(
    signal   hw_ctrl    : inout t_tb_hw_ctrl) is
  begin
    hw_ctrl.status                      <= C_TB_HW_CTRL_INIT.status;
    hw_ctrl.irq                         <= C_TB_HW_CTRL_INIT.irq;
    hw_ctrl.ext                         <= C_TB_HW_CTRL_INIT.ext;
    hw_ctrl.rx_delay                    <= C_TB_HW_CTRL_INIT.rx_delay;
    hw_ctrl.rx_nb                       <= C_TB_HW_CTRL_INIT.rx_nb;
    hw_ctrl.rx_data                     <= C_TB_HW_CTRL_INIT.rx_data;
    hw_ctrl.tx_delay                    <= C_TB_HW_CTRL_INIT.tx_delay;
  end procedure hw_init;

  -----------------------------------------------------------------------------
  -- Sequencer
  -----------------------------------------------------------------------------
  procedure do_reset(
    signal   clk        : in    std_logic;
    signal   arst_b     : out   std_logic) is
  begin
    arst_b <= '0';
    wait for 100 ns;
    wait until falling_edge(clk);
    arst_b <= '1';
    wait until rising_edge(clk);
  end procedure do_reset;

end package body tb_regtool_bfm_pkg;
