-------------------------------------------------------------------------------
-- Title      : tb_pbi_master
-- Project    : regtool
-------------------------------------------------------------------------------
-- File       : tb_pbi_master.vhd
-- Author     : Mathieu Rosiere
-- Company    :
-- Created    : 2026-10-23
-- Platform   :
-- Standard   : VHDL'08
-------------------------------------------------------------------------------
-- Description:
--  Bus master of the PBI : the access is held until busy = '0'
--  b2b : the access starts in the cycle that follows the previous one
-------------------------------------------------------------------------------
-- Copyright (c) 2026
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author   Description
-- 2026-10-23  1.0      mrosiere Created
-- 2026-11-16  1.1      mrosiere Back to back accesses (req_i.b2b)
-------------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;

library asylum;
use     asylum.pbi_pkg.all;
use     asylum.tb_regtool_pkg.all;

entity tb_pbi_master is
  port (
    clk_i      : in  std_logic;
    req_i      : in  tb_req_t;
    rsp_o      : out tb_rsp_t;

    pbi_ini_o  : out pbi_ini_t;
    pbi_tgt_i  : in  pbi_tgt_t
    );
end entity tb_pbi_master;

architecture tb of tb_pbi_master is

begin  -- architecture tb

  process is
    variable done     : boolean := false;
    variable cycles   : natural;
    variable last_end : time    := 0 ns;                    -- End of the previous access
  begin  -- process
    pbi_ini_o.cs    <= '0';
    pbi_ini_o.re    <= '0';
    pbi_ini_o.we    <= '0';
    pbi_ini_o.addr  <= (pbi_ini_o.addr 'range => '0');
    pbi_ini_o.wdata <= (pbi_ini_o.wdata'range => '0');
    rsp_o           <= TB_RSP_INIT;

    loop
      wait on req_i.start;
      -- Back to back : the request is given at the rising edge that ends
      -- the previous access, the access starts now (no idle cycle)
      if req_i.b2b then
        tb_check(now = last_end, "back to back request after the end of the previous access");
      else
        wait until rising_edge(clk_i);
      end if;

      pbi_ini_o.cs    <= '1';
      pbi_ini_o.re    <= '0' when req_i.write else '1';
      pbi_ini_o.we    <= '1' when req_i.write else '0';
      pbi_ini_o.addr  <= req_i.addr;
      pbi_ini_o.wdata <= req_i.wdata;

      -- The access is done on the rising edge where busy = '0'
      cycles  := 0;
      loop
        wait until rising_edge(clk_i);
        cycles := cycles + 1;
        exit when pbi_tgt_i.busy = '0';
      end loop;

      done     := not done;
      last_end := now;
      rsp_o    <= (done => done, rdata => pbi_tgt_i.rdata, cycles => cycles);
      pbi_ini_o.cs    <= '0';
      pbi_ini_o.re    <= '0';
      pbi_ini_o.we    <= '0';
    end loop;
  end process;

end architecture tb;
