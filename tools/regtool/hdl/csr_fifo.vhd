-------------------------------------------------------------------------------
-- Title      : csr_fifo
-- Project    : regtool
-------------------------------------------------------------------------------
-- File       : csr_fifo.vhd
-- Author     : Mathieu Rosiere
-- Company    : 
-- Created    : 2025-03-13
-- Platform   : 
-- Standard   : VHDL'93/02
-------------------------------------------------------------------------------
-- Description:
--  Interface from csr to FIFO
-------------------------------------------------------------------------------
-- Copyright (c) 2017 
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author   Description
-- 2025-03-13  1.0      mrosiere Created
-------------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

entity csr_fifo is
  
  generic (
    WIDTH : positive := 1
    ); 

  port (
    -- Clock & Reset
    clk_i         : in  std_logic;                           -- Clock
    arst_b_i      : in  std_logic;                           -- Asynchronous Reset active low

    -- Software Side
    sw_wd_i       : in  std_logic_vector(WIDTH-1 downto 0);  -- Software Side Write Data
    sw_rd_o       : out std_logic_vector(WIDTH-1 downto 0);  -- Software Side Read  Data
    sw_we_i       : in  std_logic;                           -- Software Side Write Enable
    sw_re_i       : in  std_logic;                           -- Software Side Read  Enable
    sw_busy_o     : out std_logic;                           -- Software Side Busy

    -- Hardware Side
    hw_tx_valid_i : in  std_logic;                           -- Hardware Side TX Valid
    hw_tx_ready_o : out std_logic;                           -- Hardware Side TX Ready
    hw_tx_data_i  : in  std_logic_vector(WIDTH-1 downto 0);  -- Hardware Side TX Data

    hw_rx_valid_o : out std_logic;                           -- Hardware Side RX Valid
    hw_rx_ready_i : in  std_logic;                           -- Hardware Side RX Ready
    hw_rx_data_o  : out std_logic_vector(WIDTH-1 downto 0)   -- Hardware Side RX Data
);
end entity csr_fifo;

architecture rtl of csr_fifo is
  
begin  -- architecture rtl

  hw_rx_valid_o <= sw_we_i;
  hw_rx_data_o  <= sw_wd_i;

  -- Unblocking read and unmasked
  hw_tx_ready_o <= sw_re_i;
  sw_rd_o       <= hw_tx_data_i;

  sw_busy_o     <= (sw_we_i and not hw_rx_ready_i);

end architecture rtl;
