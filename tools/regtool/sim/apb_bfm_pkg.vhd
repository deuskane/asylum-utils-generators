-------------------------------------------------------------------------------
-- Title      : apb_bfm_pkg
-- Project    : regtool
-------------------------------------------------------------------------------
-- File       : apb_bfm_pkg.vhd
-- Author     : Mathieu Rosiere
-- Company    :
-- Created    : 2026-11-16
-- Platform   :
-- Standard   : VHDL'08
-------------------------------------------------------------------------------
-- Description:
--  APB3 master BFM in the style of the UVVM BFMs (UVVM has no APB VIP) :
--  apb_write / apb_read / apb_check with msg, clock, interface record
--  t_apb_if and configuration t_apb_bfm_config, uvvm_util logs and alerts.
--  Synchronisation as the UVVM BFMs with SYNC_ON_CLOCK_ONLY : the signals
--  are driven on the falling edge, sampled on the rising edge, and the
--  procedure returns a quarter of a period after the rising edge that ends
--  the transfer, so that two calls are back to back.
--  Transfer : setup phase (psel) for one cycle, then access phase (psel,
--  penable) until pready, pslverr checked at the end of the transfer.
-------------------------------------------------------------------------------
-- Copyright (c) 2026
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author   Description
-- 2026-11-16  1.0      mrosiere Created
-------------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

library uvvm_util;
context uvvm_util.uvvm_util_context;

package apb_bfm_pkg is

  constant C_APB_BFM_SCOPE : string := "APB BFM";

  type t_apb_if is record
    psel                     : std_logic;        -- to DUT
    penable                  : std_logic;        -- to DUT
    pwrite                   : std_logic;        -- to DUT
    paddr                    : unsigned;         -- to DUT
    pwdata                   : std_logic_vector; -- to DUT
    prdata                   : std_logic_vector; -- from DUT
    pready                   : std_logic;        -- from DUT
    pslverr                  : std_logic;        -- from DUT
  end record t_apb_if;

  type t_apb_bfm_config is record
    max_wait_cycles          : natural;       -- Maximum number of cycles of the access phase before a timeout alert
    max_wait_cycles_severity : t_alert_level; -- Severity of the above timeout
    expected_pslverr         : std_logic;     -- pslverr expected at the end of the transfer
    pslverr_severity         : t_alert_level; -- Severity of a pslverr mismatch
    match_strictness         : t_match_strictness; -- Matching strictness of std_logic values in apb_check
    id_for_bfm               : t_msg_id;      -- Message ID of the BFM logs
    id_for_bfm_wait          : t_msg_id;      -- Message ID of the logs of the waits for pready
  end record t_apb_bfm_config;

  constant C_APB_BFM_CONFIG_DEFAULT : t_apb_bfm_config := (
    max_wait_cycles          => 10,
    max_wait_cycles_severity => failure,
    expected_pslverr         => '0',
    pslverr_severity         => error,
    match_strictness         => MATCH_EXACT,
    id_for_bfm               => ID_BFM,
    id_for_bfm_wait          => ID_BFM_WAIT
    );

  -- Initial values of the signals of the interface : outputs of the BFM
  -- inactive, inputs at 'Z' (driven by the DUT)
  function init_apb_if_signals(
    addr_width   : natural;
    data_width   : natural
    ) return t_apb_if;

  procedure apb_write(
    constant addr_value    : in    unsigned;
    constant data_value    : in    std_logic_vector;
    constant msg           : in    string;
    signal   clk           : in    std_logic;
    signal   apb_if        : inout t_apb_if;
    constant scope         : in    string           := C_APB_BFM_SCOPE;
    constant msg_id_panel  : in    t_msg_id_panel   := shared_msg_id_panel;
    constant config        : in    t_apb_bfm_config := C_APB_BFM_CONFIG_DEFAULT
    );

  procedure apb_read(
    constant addr_value    : in    unsigned;
    variable data_value    : out   std_logic_vector;
    constant msg           : in    string;
    signal   clk           : in    std_logic;
    signal   apb_if        : inout t_apb_if;
    constant scope         : in    string           := C_APB_BFM_SCOPE;
    constant msg_id_panel  : in    t_msg_id_panel   := shared_msg_id_panel;
    constant config        : in    t_apb_bfm_config := C_APB_BFM_CONFIG_DEFAULT;
    constant ext_proc_call : in    string           := ""  -- Set when called from another BFM procedure
    );

  -- Read, then compare the read data to data_exp ('-' : don't care bit)
  procedure apb_check(
    constant addr_value    : in    unsigned;
    constant data_exp      : in    std_logic_vector;
    constant msg           : in    string;
    signal   clk           : in    std_logic;
    signal   apb_if        : inout t_apb_if;
    constant alert_level   : in    t_alert_level    := error;
    constant scope         : in    string           := C_APB_BFM_SCOPE;
    constant msg_id_panel  : in    t_msg_id_panel   := shared_msg_id_panel;
    constant config        : in    t_apb_bfm_config := C_APB_BFM_CONFIG_DEFAULT
    );

end package apb_bfm_pkg;

package body apb_bfm_pkg is

  function init_apb_if_signals(
    addr_width   : natural;
    data_width   : natural
    ) return t_apb_if is
    variable v_if : t_apb_if(paddr (addr_width-1 downto 0),
                             pwdata(data_width-1 downto 0),
                             prdata(data_width-1 downto 0));
  begin
    v_if.psel    := '0';
    v_if.penable := '0';
    v_if.pwrite  := '0';
    v_if.paddr   := (v_if.paddr 'range => '0');
    v_if.pwdata  := (v_if.pwdata'range => '0');
    v_if.prdata  := (v_if.prdata'range => 'Z');
    v_if.pready  := 'Z';
    v_if.pslverr := 'Z';
    return v_if;
  end function init_apb_if_signals;

  -----------------------------------------------------------------------------
  -- One APB transfer : setup phase, access phase until pready, pslverr
  -----------------------------------------------------------------------------
  procedure apb_transfer(
    constant write         : in    boolean;
    constant addr_value    : in    unsigned;
    constant data_value    : in    std_logic_vector;
    variable rdata_value   : out   std_logic_vector;
    constant msg           : in    string;
    constant proc_call     : in    string;
    signal   clk           : in    std_logic;
    signal   apb_if        : inout t_apb_if;
    constant scope         : in    string;
    constant msg_id_panel  : in    t_msg_id_panel;
    constant config        : in    t_apb_bfm_config
    ) is
    variable v_addr                 : unsigned(apb_if.paddr'length-1 downto 0)          := normalize_and_check(addr_value, apb_if.paddr , ALLOW_WIDER_NARROWER, "addr_value", "apb_if.paddr" , msg);
    variable v_wdata                : std_logic_vector(apb_if.pwdata'length-1 downto 0) := normalize_and_check(data_value, apb_if.pwdata, ALLOW_NARROWER      , "data_value", "apb_if.pwdata", msg);
    variable v_cycles_waited        : natural := 0;
    variable v_time_of_rising_edge  : time    := -1 ns;
    variable v_time_of_falling_edge : time    := -1 ns;
  begin
    -- Setup phase, driven on the falling edge
    wait_on_bfm_sync_start(clk, SYNC_ON_CLOCK_ONLY, -1 ns, -1 ns, v_time_of_falling_edge, v_time_of_rising_edge);
    apb_if.psel    <= '1';
    apb_if.penable <= '0';
    apb_if.pwrite  <= '1' when write else '0';
    apb_if.paddr   <= v_addr;
    apb_if.pwdata  <= v_wdata when write else (apb_if.pwdata'range => '0');
    wait until rising_edge(clk);

    -- Access phase, until pready
    wait until falling_edge(clk);
    apb_if.penable <= '1';
    loop
      wait until rising_edge(clk);
      exit when apb_if.pready = '1';
      if v_cycles_waited = 0
      then
        log(config.id_for_bfm_wait, proc_call & " waiting for pready. " & add_msg_delimiter(msg), scope, msg_id_panel);
      end if;
      v_cycles_waited := v_cycles_waited + 1;
      if v_cycles_waited > config.max_wait_cycles
      then
        alert(config.max_wait_cycles_severity, proc_call & "=> Timeout while waiting for pready. " & add_msg_delimiter(msg), scope);
        exit;
      end if;
    end loop;

    check_value(apb_if.pslverr, config.expected_pslverr, config.pslverr_severity, "APB pslverr. " & add_msg_delimiter(msg), scope, ID_NEVER, msg_id_panel, proc_call);
    rdata_value    := apb_if.prdata;

    -- End of the transfer, a quarter of a period after the rising edge
    wait_on_bfm_exit(clk, SYNC_ON_CLOCK_ONLY, -1 ns, v_time_of_falling_edge, v_time_of_rising_edge);
    apb_if.psel    <= '0';
    apb_if.penable <= '0';
    apb_if.pwrite  <= '0';
    apb_if.paddr   <= (apb_if.paddr 'range => '0');
    apb_if.pwdata  <= (apb_if.pwdata'range => '0');
  end procedure apb_transfer;

  -----------------------------------------------------------------------------
  -- apb_write
  -----------------------------------------------------------------------------
  procedure apb_write(
    constant addr_value    : in    unsigned;
    constant data_value    : in    std_logic_vector;
    constant msg           : in    string;
    signal   clk           : in    std_logic;
    signal   apb_if        : inout t_apb_if;
    constant scope         : in    string           := C_APB_BFM_SCOPE;
    constant msg_id_panel  : in    t_msg_id_panel   := shared_msg_id_panel;
    constant config        : in    t_apb_bfm_config := C_APB_BFM_CONFIG_DEFAULT
    ) is
    constant proc_call : string := "apb_write(A:" & to_string(addr_value, HEX, AS_IS, INCL_RADIX) & ", " & to_string(data_value, HEX, AS_IS, INCL_RADIX) & ")";
    variable v_rdata   : std_logic_vector(apb_if.prdata'length-1 downto 0);
  begin
    apb_transfer(true, addr_value, data_value, v_rdata, msg, proc_call, clk, apb_if, scope, msg_id_panel, config);
    log(config.id_for_bfm, proc_call & " completed. " & add_msg_delimiter(msg), scope, msg_id_panel);
  end procedure apb_write;

  -----------------------------------------------------------------------------
  -- apb_read
  -----------------------------------------------------------------------------
  procedure apb_read(
    constant addr_value    : in    unsigned;
    variable data_value    : out   std_logic_vector;
    constant msg           : in    string;
    signal   clk           : in    std_logic;
    signal   apb_if        : inout t_apb_if;
    constant scope         : in    string           := C_APB_BFM_SCOPE;
    constant msg_id_panel  : in    t_msg_id_panel   := shared_msg_id_panel;
    constant config        : in    t_apb_bfm_config := C_APB_BFM_CONFIG_DEFAULT;
    constant ext_proc_call : in    string           := ""
    ) is
    constant local_proc_call : string := "apb_read(A:" & to_string(addr_value, HEX, AS_IS, INCL_RADIX) & ")";
    variable v_rdata         : std_logic_vector(apb_if.prdata'length-1 downto 0);
    variable v_wdata         : std_logic_vector(apb_if.pwdata'length-1 downto 0) := (others => '0');
  begin
    if ext_proc_call = ""
    then
      apb_transfer(false, addr_value, v_wdata, v_rdata, msg, local_proc_call, clk, apb_if, scope, msg_id_panel, config);
      log(config.id_for_bfm, local_proc_call & "=> " & to_string(v_rdata, HEX, SKIP_LEADING_0, INCL_RADIX) & ". " & add_msg_delimiter(msg), scope, msg_id_panel);
    else
      -- Logged by the calling procedure
      apb_transfer(false, addr_value, v_wdata, v_rdata, msg, ext_proc_call & " while executing apb_read", clk, apb_if, scope, msg_id_panel, config);
    end if;
    data_value := v_rdata;
  end procedure apb_read;

  -----------------------------------------------------------------------------
  -- apb_check
  -----------------------------------------------------------------------------
  procedure apb_check(
    constant addr_value    : in    unsigned;
    constant data_exp      : in    std_logic_vector;
    constant msg           : in    string;
    signal   clk           : in    std_logic;
    signal   apb_if        : inout t_apb_if;
    constant alert_level   : in    t_alert_level    := error;
    constant scope         : in    string           := C_APB_BFM_SCOPE;
    constant msg_id_panel  : in    t_msg_id_panel   := shared_msg_id_panel;
    constant config        : in    t_apb_bfm_config := C_APB_BFM_CONFIG_DEFAULT
    ) is
    constant proc_call  : string := "apb_check(A:" & to_string(addr_value, HEX, AS_IS, INCL_RADIX) & ", " & to_string(data_exp, HEX, AS_IS, INCL_RADIX) & ")";
    variable v_data_exp : std_logic_vector(apb_if.prdata'length-1 downto 0) := normalize_and_check(data_exp, apb_if.prdata, ALLOW_WIDER_NARROWER, "data_exp", "apb_if.prdata", msg);
    variable v_rdata    : std_logic_vector(apb_if.prdata'length-1 downto 0);
    variable v_check_ok : boolean := true;
  begin
    apb_read(addr_value, v_rdata, msg, clk, apb_if, scope, msg_id_panel, config, proc_call);

    for i in v_data_exp'range loop
      if not (v_data_exp(i) = '-' or check_value(v_rdata(i), v_data_exp(i), config.match_strictness, NO_ALERT, msg, scope, ID_NEVER))
      then
        v_check_ok := false;
        exit;
      end if;
    end loop;

    if v_check_ok
    then
      log(config.id_for_bfm, proc_call & "=> OK, read data = " & to_string(v_rdata, HEX, SKIP_LEADING_0, INCL_RADIX) & ". " & add_msg_delimiter(msg), scope, msg_id_panel);
    else
      alert(alert_level, proc_call & "=> Failed. Was " & to_string(v_rdata, HEX, AS_IS, INCL_RADIX) & ". Expected " & to_string(v_data_exp, HEX, AS_IS, INCL_RADIX) & "." & LF & add_msg_delimiter(msg), scope);
    end if;
  end procedure apb_check;

end package body apb_bfm_pkg;
