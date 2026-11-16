-------------------------------------------------------------------------------
-- Title      : tb_sbi_master
-- Project    : regtool
-------------------------------------------------------------------------------
-- File       : tb_sbi_master.vhd
-- Author     : Mathieu Rosiere
-- Company    :
-- Created    : 2026-10-23
-- Platform   :
-- Standard   : VHDL'08
-------------------------------------------------------------------------------
-- Description:
--  Bus master of the SBI : the access is held until ready = '1'
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
use     asylum.sbi_pkg.all;
use     asylum.tb_regtool_pkg.all;

entity tb_sbi_master is
  port (
    clk_i      : in  std_logic;
    req_i      : in  tb_req_t;
    rsp_o      : out tb_rsp_t;

    sbi_ini_o  : out sbi_ini_t;
    sbi_tgt_i  : in  sbi_tgt_t
    );
end entity tb_sbi_master;

architecture tb of tb_sbi_master is

begin  -- architecture tb

  process is
    variable done     : boolean := false;
    variable cycles   : natural;
    variable last_end : time    := 0 ns;                    -- End of the previous access
  begin  -- process
    sbi_ini_o.cs    <= '0';
    sbi_ini_o.re    <= '0';
    sbi_ini_o.we    <= '0';
    sbi_ini_o.addr  <= (sbi_ini_o.addr 'range => '0');
    sbi_ini_o.wdata <= (sbi_ini_o.wdata'range => '0');
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

      sbi_ini_o.cs    <= '1';
      sbi_ini_o.re    <= '0' when req_i.write else '1';
      sbi_ini_o.we    <= '1' when req_i.write else '0';
      sbi_ini_o.addr  <= req_i.addr;
      sbi_ini_o.wdata <= req_i.wdata;

      -- The access is done on the rising edge where ready = '1'
      cycles  := 0;
      loop
        wait until rising_edge(clk_i);
        cycles := cycles + 1;
        exit when sbi_tgt_i.ready = '1';
      end loop;

      done     := not done;
      last_end := now;
      rsp_o    <= (done => done, rdata => sbi_tgt_i.rdata, cycles => cycles);
      sbi_ini_o.cs    <= '0';
      sbi_ini_o.re    <= '0';
      sbi_ini_o.we    <= '0';
    end loop;
  end process;

end architecture tb;
