-------------------------------------------------------------------------------
-- Title      : sbi2mem_wrapper
-- Project    : Asylum
-------------------------------------------------------------------------------
-- File       : sbi2mem_wrapper.vhd
-- Author     : Mathieu Rosiere
-------------------------------------------------------------------------------
-- Description:
--  Wrapper (lint_ghdl_synth_sbi2mem, syn_sbi2mem) of the bridge sbi2mem
--  of regtool : the SBI records of sbi_pkg are unconstrained, the wrapper
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
use     asylum.sbi_pkg.all;

entity sbi2mem_wrapper is
  generic (
    ADDR_WIDTH     : natural := 8                    -- Memory address width
   ;DATA_WIDTH     : natural := 8                    -- Data width
  );
  port (
    -- SBI
    sbi_ini_i      : in  sbi_ini_t(addr (ADDR_WIDTH-1 downto 0),
                                    wdata(DATA_WIDTH-1 downto 0))
   ;sbi_tgt_o      : out sbi_tgt_t(rdata(DATA_WIDTH-1 downto 0))
    -- Memory interface
   ;cs_o           : out std_logic
   ;re_o           : out std_logic
   ;we_o           : out std_logic
   ;addr_o         : out std_logic_vector(ADDR_WIDTH-1 downto 0)
   ;wdata_o        : out std_logic_vector(DATA_WIDTH-1 downto 0)
   ;rdata_i        : in  std_logic_vector(DATA_WIDTH-1 downto 0)
   ;busy_i         : in  std_logic
  );
end entity sbi2mem_wrapper;

architecture rtl of sbi2mem_wrapper is

begin  -- architecture rtl

  ins_sbi2mem : entity asylum.sbi2mem
    generic map
    (ADDR_WIDTH    => ADDR_WIDTH
    ,DATA_WIDTH    => DATA_WIDTH
    )
    port map
    (sbi_ini_i     => sbi_ini_i
    ,sbi_tgt_o     => sbi_tgt_o
    ,cs_o          => cs_o
    ,re_o          => re_o
    ,we_o          => we_o
    ,addr_o        => addr_o
    ,wdata_o       => wdata_o
    ,rdata_i       => rdata_i
    ,busy_i        => busy_i
    );

end architecture rtl;
