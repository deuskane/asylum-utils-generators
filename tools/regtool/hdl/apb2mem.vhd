-------------------------------------------------------------------------------
-- Title      : apb2mem
-- Project    : regtool
-------------------------------------------------------------------------------
-- File       : apb2mem.vhd
-- Author     : Mathieu Rosiere
-- Company    :
-- Created    : 2026-10-23
-- Platform   :
-- Standard   : VHDL'93/02
-------------------------------------------------------------------------------
-- Description:
--  Bridge from an APB3 completer to the memory interface of the regtool CSR
--  (cs / re / we / addr / wdata / rdata / busy).
--  Combinational : the access is done in the access phase (psel and
--  penable), pready is '0' while the memory interface is busy.
--  pslverr is always '0' (an unmapped address reads 0).
--  APB4 pprot and pstrb are not used (full word writes).
-------------------------------------------------------------------------------
-- Copyright (c) 2026
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author   Description
-- 2026-10-23  1.0      mrosiere Created
-------------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;

entity apb2mem is

  generic (
    ADDR_WIDTH : natural := 8;                               -- Address Width
    DATA_WIDTH : natural := 32                               -- Data Width
    );

  port (
    -- APB
    s_apb_psel_i    : in  std_logic;                         -- Select
    s_apb_penable_i : in  std_logic;                         -- Enable (access phase)
    s_apb_pwrite_i  : in  std_logic;                         -- '1' : write, '0' : read
    s_apb_paddr_i   : in  std_logic_vector(ADDR_WIDTH-1 downto 0); -- Address
    s_apb_pwdata_i  : in  std_logic_vector(DATA_WIDTH-1 downto 0); -- Write Data
    s_apb_prdata_o  : out std_logic_vector(DATA_WIDTH-1 downto 0); -- Read  Data
    s_apb_pready_o  : out std_logic;                         -- Ready
    s_apb_pslverr_o : out std_logic;                         -- Error
    -- Memory Interface
    cs_o            : out std_logic;                         -- Chip Select
    re_o            : out std_logic;                         -- Read  Enable
    we_o            : out std_logic;                         -- Write Enable
    addr_o          : out std_logic_vector(ADDR_WIDTH-1 downto 0); -- Address
    wdata_o         : out std_logic_vector(DATA_WIDTH-1 downto 0); -- Write Data
    rdata_i         : in  std_logic_vector(DATA_WIDTH-1 downto 0); -- Read  Data
    busy_i          : in  std_logic                          -- Access not completed
    );
end entity apb2mem;

architecture rtl of apb2mem is

  signal access_phase : std_logic;

begin  -- architecture rtl

  access_phase    <= s_apb_psel_i and s_apb_penable_i;

  cs_o            <= access_phase;
  re_o            <= access_phase and not s_apb_pwrite_i;
  we_o            <= access_phase and     s_apb_pwrite_i;
  addr_o          <= s_apb_paddr_i;
  wdata_o         <= s_apb_pwdata_i;

  s_apb_prdata_o  <= rdata_i;
  s_apb_pready_o  <= not busy_i;
  s_apb_pslverr_o <= '0';

end architecture rtl;
