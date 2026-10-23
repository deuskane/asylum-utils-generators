-------------------------------------------------------------------------------
-- Title      : sbi2mem
-- Project    : regtool
-------------------------------------------------------------------------------
-- File       : sbi2mem.vhd
-- Author     : Mathieu Rosiere
-- Company    :
-- Created    : 2026-10-23
-- Platform   :
-- Standard   : VHDL'08
-------------------------------------------------------------------------------
-- Description:
--  Bridge from an SBI target to the memory interface of the regtool CSR
--  (cs / re / we / addr / wdata / rdata / busy).
--  Combinational : the access is held by the initiator while ready = '0'.
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
use     asylum.sbi_pkg.all;

entity sbi2mem is

  generic (
    ADDR_WIDTH : natural := 8;                               -- Memory Address Width (LSB of sbi_ini_i.addr)
    DATA_WIDTH : natural := 8;                               -- Data Width (sbi_ini_i.wdata'length)
    NAME       : string  := ""                               -- Target Name (sbi_tgt_o.info.name)
    );

  port (
    -- SBI
    sbi_ini_i     : in  sbi_ini_t;                           -- SBI Initiator to Target
    sbi_tgt_o     : out sbi_tgt_t;                           -- SBI Target to Initiator
    -- Memory Interface
    cs_o          : out std_logic;                           -- Chip Select
    re_o          : out std_logic;                           -- Read  Enable
    we_o          : out std_logic;                           -- Write Enable
    addr_o        : out std_logic_vector(ADDR_WIDTH-1 downto 0); -- Address
    wdata_o       : out std_logic_vector(DATA_WIDTH-1 downto 0); -- Write Data
    rdata_i       : in  std_logic_vector(DATA_WIDTH-1 downto 0); -- Read  Data
    busy_i        : in  std_logic                            -- Access not completed
    );
end entity sbi2mem;

architecture rtl of sbi2mem is

begin  -- architecture rtl

  cs_o                <= sbi_ini_i.cs;
  re_o                <= sbi_ini_i.re;
  we_o                <= sbi_ini_i.we;
  addr_o              <= sbi_ini_i.addr(ADDR_WIDTH-1 downto 0);
  wdata_o             <= sbi_ini_i.wdata;

  sbi_tgt_o.rdata     <= rdata_i;
  sbi_tgt_o.ready     <= not busy_i;
  sbi_tgt_o.info.name <= to_sbi_name(NAME);

end architecture rtl;
