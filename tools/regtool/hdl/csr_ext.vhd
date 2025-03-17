-------------------------------------------------------------------------------
-- Title      : csr_ext
-- Project    : regtool
-------------------------------------------------------------------------------
-- File       : csr_ext.vhd
-- Author     : Mathieu Rosiere
-- Company    : 
-- Created    : 2025-03-13
-- Platform   : 
-- Standard   : VHDL'93/02
-------------------------------------------------------------------------------
-- Description:
--  Macro from https://opentitan.org/book/util/reggen/index.html
-------------------------------------------------------------------------------
-- Copyright (c) 2017 
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author   Description
-- 2025-03-13  1.0      mrosiere Created
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity csr_ext is
  
  generic (
    WIDTH : positive := 1                                 -- Register Width
    ); 

  port (
    -- Clock & Reset
    clk_i         : in  std_logic;                            -- Clock
    arst_b_i      : in  std_logic;                            -- Asynchronous Reset active low
    -- Software Side
    sw_wd_i       : in  std_logic_vector(WIDTH-1 downto 0);  -- Software Side Write Data
    sw_rd_o       : out std_logic_vector(WIDTH-1 downto 0);  -- Software Side Read  Data
    sw_we_i       : in  std_logic;                           -- Software Side Write Enable
    sw_re_i       : in  std_logic;                           -- Software Side Read  Enable
    sw_busy_o     : out std_logic;                           -- Software Side Busy
    -- Hardware Side
    hw_wd_i       : in  std_logic_vector(WIDTH-1 downto 0);  -- Hardware Side Write Data
    hw_rd_o       : out std_logic_vector(WIDTH-1 downto 0);  -- Hardware Side Read  Data
    hw_we_i       : in  std_logic;                           -- Hardware Side Write Enable
    hw_sw_re_o    : out std_logic;                           -- Hardware Side CSR was Read
    hw_sw_we_o    : out std_logic                            -- Hardware Side CSR was Write
);
end entity csr_ext;

architecture rtl of csr_ext is
  
begin  -- architecture rtl

  sw_busy_o  <= '0';
  sw_rd_o    <= hw_wd_i;
  hw_rd_o    <= sw_wd_i;
  hw_sw_re_o <= sw_we_i; 
  hw_sw_we_o <= sw_re_i;
  
end architecture rtl;
