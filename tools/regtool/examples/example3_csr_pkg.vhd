-- Generated VHDL Package for example3

library IEEE;
use     IEEE.STD_LOGIC_1164.ALL;
use     IEEE.NUMERIC_STD.ALL;

--==================================
-- Module      : example3
-- Description : test
-- Width       : 32
--==================================

package example3_csr_pkg is

  ------------------------------------
  -- Global Constants
  ------------------------------------

  constant EXAMPLE3_ADDR_WIDTH : natural := 0;
  constant EXAMPLE3_DATA_WIDTH : natural := 32;

  --==================================
  -- Register    : regA
  -- Description : A
  -- Address     : 0x0
  -- Width       : 16
  -- Sw Access   : rw
  -- Hw Access   : ro
  -- Hw Type     : reg
  --==================================
  constant EXAMPLE3_REGA : unsigned(EXAMPLE3_ADDR_WIDTH-1 downto 0) := to_unsigned(0, EXAMPLE3_ADDR_WIDTH);

  type example3_regA_sw2hw_t is record
    re : std_logic;
    we : std_logic;
  --==================================
  -- Field       : a
  -- Description : a
  -- Width       : 8
  --==================================
    a : std_logic_vector(8-1 downto 0);
  --==================================
  -- Field       : b
  -- Description : b
  -- Width       : 8
  --==================================
    b : std_logic_vector(8-1 downto 0);
  end record example3_regA_sw2hw_t;

  ------------------------------------
  -- Structure example3_t
  ------------------------------------
  type example3_sw2hw_t is record
    regA : example3_regA_sw2hw_t;
  end record example3_sw2hw_t;

  ------------------------------------
  -- Component
  ------------------------------------
component example3_registers is
  generic (
    MODULE_NAME :  string := "" -- Name of the module
  );
  port (
    -- Clock and Reset
    clk_i      : in  std_logic
   ;arst_b_i   : in  std_logic
    -- Bus
   ;cs_i       : in    std_logic
   ;re_i       : in    std_logic
   ;we_i       : in    std_logic
   ;addr_i     : in    std_logic_vector (0-1 downto 0)
   ;wdata_i    : in    std_logic_vector (32-1 downto 0)
   ;rdata_o    : out   std_logic_vector (32-1 downto 0)
   ;busy_o     : out   std_logic
    -- CSR
   ;sw2hw_o    : out example3_sw2hw_t
  );
end component example3_registers;


end package example3_csr_pkg;
