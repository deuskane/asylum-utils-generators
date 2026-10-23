-------------------------------------------------------------------------------
-- Title      : pbi2mem
-- Project    : regtool
-------------------------------------------------------------------------------
-- File       : pbi2mem.vhd
-- Author     : Mathieu Rosiere
-- Company    :
-- Created    : 2026-10-23
-- Platform   :
-- Standard   : VHDL'08
-------------------------------------------------------------------------------
-- Description:
--  Bridge from a PBI target to the memory interface of the regtool CSR
--  (cs / re / we / addr / wdata / rdata / busy).
--  Combinational : the access is held by the initiator while busy = '1'.
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
use     asylum.pbi_pkg.all;

entity pbi2mem is

  generic (
    ADDR_WIDTH : natural := 8;                               -- Memory Address Width (LSB of pbi_ini_i.addr)
    DATA_WIDTH : natural := 8                                -- Data Width (pbi_ini_i.wdata'length)
    );

  port (
    -- PBI
    pbi_ini_i     : in  pbi_ini_t;                           -- PBI Initiator to Target
    pbi_tgt_o     : out pbi_tgt_t;                           -- PBI Target to Initiator
    -- Memory Interface
    cs_o          : out std_logic;                           -- Chip Select
    re_o          : out std_logic;                           -- Read  Enable
    we_o          : out std_logic;                           -- Write Enable
    addr_o        : out std_logic_vector(ADDR_WIDTH-1 downto 0); -- Address
    wdata_o       : out std_logic_vector(DATA_WIDTH-1 downto 0); -- Write Data
    rdata_i       : in  std_logic_vector(DATA_WIDTH-1 downto 0); -- Read  Data
    busy_i        : in  std_logic                            -- Access not completed
    );
end entity pbi2mem;

architecture rtl of pbi2mem is

begin  -- architecture rtl

  cs_o            <= pbi_ini_i.cs;
  re_o            <= pbi_ini_i.re;
  we_o            <= pbi_ini_i.we;
  addr_o          <= pbi_ini_i.addr(ADDR_WIDTH-1 downto 0);
  wdata_o         <= pbi_ini_i.wdata;

  pbi_tgt_o.rdata <= rdata_i;
  pbi_tgt_o.busy  <= busy_i;

end architecture rtl;
