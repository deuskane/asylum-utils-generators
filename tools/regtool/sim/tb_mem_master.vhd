-------------------------------------------------------------------------------
-- Title      : tb_mem_master
-- Project    : regtool
-------------------------------------------------------------------------------
-- File       : tb_mem_master.vhd
-- Author     : Mathieu Rosiere
-- Company    :
-- Created    : 2026-10-23
-- Platform   :
-- Standard   : VHDL'08
-------------------------------------------------------------------------------
-- Description:
--  Bus master of the memory interface : the access is held until busy = '0'
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
use     asylum.tb_regtool_pkg.all;

entity tb_mem_master is
  generic (
    ADDR_WIDTH : natural := 8
    );
  port (
    clk_i      : in  std_logic;
    req_i      : in  tb_req_t;
    rsp_o      : out tb_rsp_t;

    cs_o       : out std_logic;
    re_o       : out std_logic;
    we_o       : out std_logic;
    addr_o     : out std_logic_vector(ADDR_WIDTH-1 downto 0);
    wdata_o    : out std_logic_vector(TB_DATA_WIDTH-1 downto 0);
    rdata_i    : in  std_logic_vector(TB_DATA_WIDTH-1 downto 0);
    busy_i     : in  std_logic
    );
end entity tb_mem_master;

architecture tb of tb_mem_master is

begin  -- architecture tb

  process is
    variable done     : boolean := false;
    variable cycles   : natural;
    variable last_end : time    := 0 ns;                    -- End of the previous access
  begin  -- process
    cs_o    <= '0';
    re_o    <= '0';
    we_o    <= '0';
    addr_o  <= (others => '0');
    wdata_o <= (others => '0');
    rsp_o   <= TB_RSP_INIT;

    loop
      wait on req_i.start;
      -- Back to back : the request is given at the rising edge that ends
      -- the previous access, the access starts now (no idle cycle)
      if req_i.b2b then
        tb_check(now = last_end, "back to back request after the end of the previous access");
      else
        wait until rising_edge(clk_i);
      end if;

      cs_o    <= '1';
      re_o    <= '0' when req_i.write else '1';
      we_o    <= '1' when req_i.write else '0';
      addr_o  <= req_i.addr(ADDR_WIDTH-1 downto 0);
      wdata_o <= req_i.wdata;

      -- The access is done on the rising edge where busy = '0'
      cycles  := 0;
      loop
        wait until rising_edge(clk_i);
        cycles := cycles + 1;
        exit when busy_i = '0';
      end loop;

      done     := not done;
      last_end := now;
      rsp_o    <= (done => done, rdata => rdata_i, cycles => cycles);
      cs_o     <= '0';
      re_o     <= '0';
      we_o     <= '0';
    end loop;
  end process;

end architecture tb;
