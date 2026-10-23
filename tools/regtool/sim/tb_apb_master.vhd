-------------------------------------------------------------------------------
-- Title      : tb_apb_master
-- Project    : regtool
-------------------------------------------------------------------------------
-- File       : tb_apb_master.vhd
-- Author     : Mathieu Rosiere
-- Company    :
-- Created    : 2026-10-23
-- Platform   :
-- Standard   : VHDL'08
-------------------------------------------------------------------------------
-- Description:
--  APB3 requester : setup phase, then access phase until pready = '1'
--  (pslverr must be '0')
-------------------------------------------------------------------------------
-- Copyright (c) 2026
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author   Description
-- 2026-10-23  1.0      mrosiere Created
-------------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;

library asylum;
use     asylum.tb_regtool_pkg.all;

entity tb_apb_master is
  generic (
    ADDR_WIDTH : natural := 8
    );
  port (
    clk_i      : in  std_logic;
    req_i      : in  tb_req_t;
    rsp_o      : out tb_rsp_t;

    psel_o     : out std_logic;
    penable_o  : out std_logic;
    pwrite_o   : out std_logic;
    paddr_o    : out std_logic_vector(ADDR_WIDTH-1 downto 0);
    pwdata_o   : out std_logic_vector(TB_DATA_WIDTH-1 downto 0);
    prdata_i   : in  std_logic_vector(TB_DATA_WIDTH-1 downto 0);
    pready_i   : in  std_logic;
    pslverr_i  : in  std_logic
    );
end entity tb_apb_master;

architecture tb of tb_apb_master is

begin  -- architecture tb

  process is
    variable done   : boolean := false;
    variable cycles : natural;
  begin  -- process
    psel_o    <= '0';
    penable_o <= '0';
    pwrite_o  <= '0';
    paddr_o   <= (others => '0');
    pwdata_o  <= (others => '0');
    rsp_o     <= TB_RSP_INIT;

    loop
      wait on req_i.start;
      wait until rising_edge(clk_i);

      -- Setup phase
      psel_o    <= '1';
      pwrite_o  <= '1' when req_i.write else '0';
      paddr_o   <= req_i.addr(ADDR_WIDTH-1 downto 0);
      pwdata_o  <= req_i.wdata;
      wait until rising_edge(clk_i);

      -- Access phase, until pready
      penable_o <= '1';
      cycles    := 1;
      loop
        wait until rising_edge(clk_i);
        cycles := cycles + 1;
        exit when pready_i = '1';
      end loop;

      tb_check(pslverr_i = '0', "APB pslverr");

      done      := not done;
      rsp_o     <= (done => done, rdata => prdata_i, cycles => cycles);
      psel_o    <= '0';
      penable_o <= '0';
    end loop;
  end process;

end architecture tb;
