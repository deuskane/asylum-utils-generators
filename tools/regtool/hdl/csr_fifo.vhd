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
-- 2025-04-19  1.1      mrosiere Add Blocking Write / Read
-- 2025-07-09  1.2      mrosiere Add FIFO
-------------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

library work;
use     work.fifo_pkg.all;

entity csr_fifo is
  
  generic (
    WIDTH          : positive := 1    ;
    BLOCKING_READ  : boolean  := false;
    BLOCKING_WRITE : boolean  := true ;
    DEPTH_SW2HW    : natural  := 0    ;
    DEPTH_HW2SW    : natural  := 0    
    ); 

  port (
    -- Clock & Reset
    clk_i                : in  std_logic;                           -- Clock
    arst_b_i             : in  std_logic;                           -- Asynchronous Reset active low

    -- Software Side
    sw_wd_i              : in  std_logic_vector(WIDTH-1 downto 0);  -- Software Side Write Data
    sw_rd_o              : out std_logic_vector(WIDTH-1 downto 0);  -- Software Side Read  Data
    sw_we_i              : in  std_logic;                           -- Software Side Write Enable
    sw_re_i              : in  std_logic;                           -- Software Side Read  Enable
    sw_rbusy_o           : out std_logic;                           -- Software Side Read  Busy
    sw_wbusy_o           : out std_logic;                           -- Software Side Write Busy

    -- Hardware Side
    hw_tx_valid_i        : in  std_logic;                           -- Hardware Side TX Valid
    hw_tx_ready_o        : out std_logic;                           -- Hardware Side TX Ready
    hw_tx_data_i         : in  std_logic_vector(WIDTH-1 downto 0);  -- Hardware Side TX Data
  --hw_tx_nb_elt_empty_o : out std_logic_vector;                    -- Number of free slot
  --hw_tx_nb_elt_full_o  : out std_logic_vector;                    -- Number of filled slot
    hw_tx_empty_o        : out std_logic;                           -- Hardware Side TX Empty Flag
    hw_tx_full_o         : out std_logic;                           -- Hardware Side TX Full  Flag
    
    hw_rx_valid_o        : out std_logic;                           -- Hardware Side RX Valid
    hw_rx_ready_i        : in  std_logic;                           -- Hardware Side RX Ready
    hw_rx_data_o         : out std_logic_vector(WIDTH-1 downto 0);  -- Hardware Side RX Data
  --hw_rx_nb_elt_empty_o : out std_logic_vector;                    -- Number of free slot
  --hw_rx_nb_elt_full_o  : out std_logic_vector;                    -- Number of filled slot
    hw_rx_empty_o        : out std_logic;                           -- Hardware Side RX Empty Flag
    hw_rx_full_o         : out std_logic                            -- Hardware Side RX Full  Flag
);
end entity csr_fifo;

architecture rtl of csr_fifo is

  signal full          : std_ulogic;
  signal full_b        : std_ulogic;
  signal empty         : std_ulogic;
  signal empty_b       : std_ulogic;
  
begin  -- architecture rtl

  gen_depth_sw2hw_eq_0  : if DEPTH_SW2HW = 0
  generate
    hw_rx_valid_o           <= sw_we_i;
    hw_rx_data_o            <= sw_wd_i;
                            
    full_b                  <= hw_rx_ready_i;
    full                    <= not full_b ;
                            
    hw_rx_empty_o           <= full_b;
    hw_rx_full_o            <= full  ;
  --hw_rx_nb_elt_empty_o(0) <= full_b;
  --hw_rx_nb_elt_full_o (0) <= full  ;
    
  end generate gen_depth_sw2hw_eq_0;
  
  gen_depth_sw2hw_ne_0  : if DEPTH_SW2HW /= 0
  generate
    ins_fifo_sw2hw : fifo_sync
      generic map
      (
        WIDTH                  => WIDTH
       ,DEPTH                  => DEPTH_SW2HW
        )
      port map
      (                   
        clk_i                  => clk_i
       ,arst_b_i               => arst_b_i
       ,s_axis_tvalid_i        => sw_we_i
       ,s_axis_tready_o        => full_b
       ,s_axis_tdata_i         => sw_wd_i
       ,s_axis_nb_elt_empty_o  => open
       ,s_axis_full_o          => full
       ,s_axis_empty_o         => open
        
       ,m_axis_tvalid_o        => hw_rx_valid_o
       ,m_axis_tready_i        => hw_rx_ready_i
       ,m_axis_tdata_o         => hw_rx_data_o
       ,m_axis_nb_elt_full_o   => open
       ,m_axis_full_o          => hw_rx_full_o 
       ,m_axis_empty_o         => hw_rx_empty_o
       );
    
  end generate gen_depth_sw2hw_ne_0;

  gen_depth_hw2sw_eq_0  : if DEPTH_HW2SW = 0
  generate
    hw_tx_ready_o           <= sw_re_i;
    sw_rd_o                 <= hw_tx_data_i; -- Unmasked Read
                            
    empty_b                 <= hw_tx_valid_i;
    empty                   <= not empty_b;

    hw_tx_empty_o           <= empty  ;
    hw_tx_full_o            <= empty_b;
  --hw_tx_nb_elt_empty_o(0) <= empty  ;
  --hw_tx_nb_elt_full_o (0) <= empty_b;

  end generate gen_depth_hw2sw_eq_0;
  
  gen_depth_hw2sw_ne_0  : if DEPTH_HW2SW /= 0
  generate

    ins_fifo_hw2sw : fifo_sync
      generic map
      (
        WIDTH                  => WIDTH
       ,DEPTH                  => DEPTH_HW2SW
        )
      port map
      (                   
        clk_i                  => clk_i
       ,arst_b_i               => arst_b_i
       ,s_axis_tvalid_i        => hw_tx_valid_i 
       ,s_axis_tready_o        => hw_tx_ready_o 
       ,s_axis_tdata_i         => hw_tx_data_i  
       ,s_axis_nb_elt_empty_o  => open
       ,s_axis_full_o          => hw_tx_full_o 
       ,s_axis_empty_o         => hw_tx_empty_o

       ,m_axis_tvalid_o        => empty_b
       ,m_axis_tready_i        => sw_re_i
       ,m_axis_tdata_o         => sw_rd_o
       ,m_axis_nb_elt_full_o   => open
       ,m_axis_full_o          => open
       ,m_axis_empty_o         => empty
       );
    
  end generate gen_depth_hw2sw_ne_0;
  
  
  gen_blocking_write  : if BLOCKING_WRITE = true
  generate
    sw_wbusy_o    <= full;
  end generate gen_blocking_write;

  gen_blocking_write_b: if BLOCKING_WRITE = false
  generate
    sw_wbusy_o    <= '0';
  end generate gen_blocking_write_b;

  gen_blocking_read  : if BLOCKING_READ = true
  generate
    sw_rbusy_o    <= empty;
  end generate gen_blocking_read;

  gen_blocking_read_b: if BLOCKING_READ = false
  generate
    sw_rbusy_o    <= '0';
  end generate gen_blocking_read_b;
  
end architecture rtl;
