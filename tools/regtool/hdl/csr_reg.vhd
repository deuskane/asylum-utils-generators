-------------------------------------------------------------------------------
-- Title      : csr_reg
-- Project    : regtool
-------------------------------------------------------------------------------
-- File       : csr_reg.vhd
-- Author     : Mathieu Rosiere
-- Company    : 
-- Created    : 2025-02-09
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
-- 2025-02-09  1.0      mrosiere Created
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity csr_reg is
  
  generic (
    WIDTH : positive := 1;                              -- Register Width
    INIT  : std_logic_vector;                           -- Reset
    MODEL : string                                      -- "rw", "rw1c", "rw0c", "rw1s", "rw0s"
                              
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
    sw_rbusy_o    : out std_logic;                           -- Software Side Read  Busy
    sw_wbusy_o    : out std_logic;                           -- Software Side Write Busy
    -- Hardware Side
    hw_wd_i       : in  std_logic_vector(WIDTH-1 downto 0);  -- Hardware Side Write Data
    hw_rd_o       : out std_logic_vector(WIDTH-1 downto 0);  -- Hardware Side Read  Data
    hw_we_i       : in  std_logic;                           -- Hardware Side Write Enable
    hw_sw_re_o    : out std_logic;                           -- Hardware Side CSR was Read
    hw_sw_we_o    : out std_logic                            -- Hardware Side CSR was Write
    );
end entity csr_reg;

architecture rtl of csr_reg is

  signal q_r       : std_logic_vector(WIDTH-1 downto 0);
  signal q_sw_we_r : std_logic;
  signal q_sw_re_r : std_logic;
  signal q_r_next  : std_logic_vector(WIDTH-1 downto 0);
  signal d_hw      : std_logic_vector(WIDTH-1 downto 0);
  signal d_sw      : std_logic_vector(WIDTH-1 downto 0);
  
begin  -- architecture rtl

  gen_ro: if MODEL="ro" generate
    q_r_next <= hw_wd_i when hw_we_i = '1' else
                q_r;
  end generate gen_ro;

  gen_rw: if MODEL="rw" generate
    q_r_next <= sw_wd_i when sw_we_i = '1' else
                hw_wd_i when hw_we_i = '1' else
                q_r;
  end generate gen_rw;

  gen_rw1c: if MODEL="rw1c" generate
    d_hw     <= hw_wd_i when hw_we_i = '1' else
                q_r;
    d_sw     <= not sw_wd_i when sw_we_i = '1' else
                (others => '1');
    
    q_r_next <= d_hw and d_sw;
  end generate gen_rw1c;

  gen_rw0c: if MODEL="rw0c" generate
    d_hw     <= hw_wd_i when hw_we_i = '1' else
                q_r;
    d_sw     <= sw_wd_i when sw_we_i = '1' else
                (others => '1');
    
    q_r_next <= d_hw and d_sw;
  end generate gen_rw0c;

  gen_rw1s: if MODEL="rw1s" generate
    d_hw     <= hw_wd_i when hw_we_i = '1' else
                q_r;
    d_sw     <= sw_wd_i when sw_we_i = '1' else
                (others => '0');
    
    q_r_next <= d_hw or d_sw;
  end generate gen_rw1s;

  gen_rw0s: if MODEL="rw0s" generate
    d_hw     <= hw_wd_i when hw_we_i = '1' else
                q_r;
    d_sw     <= not sw_wd_i when sw_we_i = '1' else
                (others => '0');
    
    q_r_next <= d_hw or d_sw;
  end generate gen_rw0s;

  process (clk_i, arst_b_i) is
  begin  -- process
    if arst_b_i = '0' then              -- asynchronous reset (active low)
      q_r       <= INIT;
      q_sw_we_r <= '0';
      q_sw_re_r <= '0';
    elsif clk_i'event and clk_i = '1' then  -- rising clock edge
      q_r       <= q_r_next;
      q_sw_we_r <= sw_we_i;
      q_sw_re_r <= sw_re_i;
    end if;
  end process;

  hw_sw_re_o <= q_sw_we_r;
  hw_sw_we_o <= q_sw_re_r;
  hw_rd_o    <= q_r      ;
  sw_rd_o    <= q_r      ;
  sw_rbusy_o <= '0';
  sw_wbusy_o <= '0';
  
end architecture rtl;
