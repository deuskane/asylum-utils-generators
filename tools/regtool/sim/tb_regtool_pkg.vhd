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
--  Types and procedures of the regtool testbenches :
--  the scenario (tb_regtool_scenario) sends an access request (tb_req_t)
--  to the bus master of the interface (tb_<interface>_master), the master
--  does the access on the bus and returns the response (tb_rsp_t)
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

package tb_regtool_pkg is

  constant TB_ADDR_WIDTH : natural := 8;
  constant TB_DATA_WIDTH : natural := 32;
  constant TB_PERIOD     : time    := 10 ns;

  -- Access request : a new access each time start toggles
  type tb_req_t is record
    start        : boolean;
    write        : boolean;
    addr         : std_logic_vector(TB_ADDR_WIDTH-1 downto 0);
    wdata        : std_logic_vector(TB_DATA_WIDTH-1 downto 0);
  end record tb_req_t;

  -- Access response : done toggles at the end of the access
  type tb_rsp_t is record
    done         : boolean;
    rdata        : std_logic_vector(TB_DATA_WIDTH-1 downto 0);
    cycles       : natural;                                  -- Clock cycles of the access
  end record tb_rsp_t;

  constant TB_REQ_INIT : tb_req_t := (start => false, write => false, addr => (others => '0'), wdata => (others => '0'));
  constant TB_RSP_INIT : tb_rsp_t := (done  => false, rdata => (others => '0'), cycles => 0);

  -- Stop the simulation with a failure if the condition is false
  procedure tb_check      (cond : boolean; msg : string);

  -- Stop the simulation with a failure if value /= expected
  procedure tb_check_equal(value, expected : std_logic_vector; msg : string);

end package tb_regtool_pkg;

package body tb_regtool_pkg is

  procedure tb_check (cond : boolean; msg : string) is
  begin
    assert cond report "[TESTBENCH] ERROR : " & msg severity failure;
  end procedure tb_check;

  procedure tb_check_equal(value, expected : std_logic_vector; msg : string) is
  begin
    assert value = expected
      report "[TESTBENCH] ERROR : " & msg & " : 0x" & to_hstring(value) & " instead of 0x" & to_hstring(expected)
      severity failure;
  end procedure tb_check_equal;

end package body tb_regtool_pkg;
