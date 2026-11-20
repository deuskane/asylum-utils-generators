-------------------------------------------------------------------------------
-- Title      : csr_reg_wrapper
-- Project    : Asylum
-------------------------------------------------------------------------------
-- File       : csr_reg_wrapper.vhd
-- Author     : Mathieu Rosiere
-------------------------------------------------------------------------------
-- Description:
--  Wrapper (lint_ghdl_synth_csr_reg_*, syn_csr_reg_*) of one csr_reg, the
--  register of the regtool building blocks : csr_reg has generics without
--  default (INIT, MODEL) and cannot be a top.
--  INIT is unconstrained (length WIDTH) : with GHDL 6.0.0, the override (-g)
--  of a generic whose subtype depends on another generic fails at
--  elaboration (NULL access) when it is forwarded to an instance.
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
use     asylum.csr_pkg.all;

entity csr_reg_wrapper is
  generic (
    WIDTH          : positive         := 8           -- Register width
   ;INIT           : std_logic_vector := "00000000"  -- Reset value (WIDTH bits)
   ;MODEL          : string           := "rw"        -- Software access model
   ;RD_WAIT_STATE  : natural          := 0           -- Wait states of a software read
   ;WR_WAIT_STATE  : natural          := 0           -- Wait states of a software write
  );
  port (
    -- Clock and Reset
    clk_i          : in  std_logic
   ;arst_b_i       : in  std_logic
    -- Software side
   ;sw_wd_i        : in  std_logic_vector(WIDTH-1 downto 0)
   ;sw_rd_o        : out std_logic_vector(WIDTH-1 downto 0)
   ;sw_we_i        : in  std_logic
   ;sw_re_i        : in  std_logic
   ;sw_rbusy_o     : out std_logic
   ;sw_wbusy_o     : out std_logic
    -- Hardware side
   ;hw_wd_i        : in  std_logic_vector(WIDTH-1 downto 0)
   ;hw_rd_o        : out std_logic_vector(WIDTH-1 downto 0)
   ;hw_we_i        : in  std_logic
   ;hw_sw_re_o     : out std_logic
   ;hw_sw_we_o     : out std_logic
  );
end entity csr_reg_wrapper;

architecture rtl of csr_reg_wrapper is

begin  -- architecture rtl

  ins_csr_reg : csr_reg
    generic map
    (WIDTH         => WIDTH
    ,INIT          => INIT
    ,MODEL         => MODEL
    ,RD_WAIT_STATE => RD_WAIT_STATE
    ,WR_WAIT_STATE => WR_WAIT_STATE
    )
    port map
    (clk_i         => clk_i
    ,arst_b_i      => arst_b_i
    ,sw_wd_i       => sw_wd_i
    ,sw_rd_o       => sw_rd_o
    ,sw_we_i       => sw_we_i
    ,sw_re_i       => sw_re_i
    ,sw_rbusy_o    => sw_rbusy_o
    ,sw_wbusy_o    => sw_wbusy_o
    ,hw_wd_i       => hw_wd_i
    ,hw_rd_o       => hw_rd_o
    ,hw_we_i       => hw_we_i
    ,hw_sw_re_o    => hw_sw_re_o
    ,hw_sw_we_o    => hw_sw_we_o
    );

end architecture rtl;
