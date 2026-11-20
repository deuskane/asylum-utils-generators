-------------------------------------------------------------------------------
-- Title      : pbi2mem_wrapper
-- Project    : Asylum
-------------------------------------------------------------------------------
-- File       : pbi2mem_wrapper.vhd
-- Author     : Mathieu Rosiere
-------------------------------------------------------------------------------
-- Description:
--  Wrapper (lint_ghdl_synth_pbi2mem, syn_pbi2mem) of the bridge pbi2mem
--  of regtool : the PBI records of pbi_pkg are unconstrained, the wrapper
--  constrains them to ADDR_WIDTH / DATA_WIDTH.
-------------------------------------------------------------------------------
-- Copyright (c) 2026
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author   Description
-- 2026-11-20  1.0      mrosiere Created (one wrapper per building block)
-------------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;

library asylum;
use     asylum.pbi_pkg.all;

entity pbi2mem_wrapper is
  generic (
    ADDR_WIDTH     : natural := 8                    -- Memory address width
   ;DATA_WIDTH     : natural := 8                    -- Data width
  );
  port (
    -- PBI
    pbi_ini_i      : in  pbi_ini_t(addr (ADDR_WIDTH-1 downto 0),
                                    wdata(DATA_WIDTH-1 downto 0))
   ;pbi_tgt_o      : out pbi_tgt_t(rdata(DATA_WIDTH-1 downto 0))
    -- Memory interface
   ;cs_o           : out std_logic
   ;re_o           : out std_logic
   ;we_o           : out std_logic
   ;addr_o         : out std_logic_vector(ADDR_WIDTH-1 downto 0)
   ;wdata_o        : out std_logic_vector(DATA_WIDTH-1 downto 0)
   ;rdata_i        : in  std_logic_vector(DATA_WIDTH-1 downto 0)
   ;busy_i         : in  std_logic
  );
end entity pbi2mem_wrapper;

architecture rtl of pbi2mem_wrapper is

begin  -- architecture rtl

  ins_pbi2mem : entity asylum.pbi2mem
    generic map
    (ADDR_WIDTH    => ADDR_WIDTH
    ,DATA_WIDTH    => DATA_WIDTH
    )
    port map
    (pbi_ini_i     => pbi_ini_i
    ,pbi_tgt_o     => pbi_tgt_o
    ,cs_o          => cs_o
    ,re_o          => re_o
    ,we_o          => we_o
    ,addr_o        => addr_o
    ,wdata_o       => wdata_o
    ,rdata_i       => rdata_i
    ,busy_i        => busy_i
    );

end architecture rtl;
