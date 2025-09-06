-- Generated VHDL Package for example1

library IEEE;
use     IEEE.STD_LOGIC_1164.ALL;
use     IEEE.NUMERIC_STD.ALL;

--==================================
-- Module      : example1
-- Description : The example 1
-- Width       : 32
--==================================

package example1_csr_pkg is

  --==================================
  -- Register    : reg1
  -- Description : Register 1
  -- Address     : 0x0
  -- Width       : 2
  -- Sw Access   : rw1c
  -- Hw Access   : rw
  -- Hw Type     : reg
  --==================================
  type example1_reg1_sw2hw_t is record
    re : std_logic;
    we : std_logic;
  --==================================
  -- Field       : field1
  -- Description : Field 1
  -- Width       : 1
  --==================================
    field1 : std_logic_vector(1-1 downto 0);
  --==================================
  -- Field       : field2
  -- Description : Field 2
  -- Width       : 1
  --==================================
    field2 : std_logic_vector(1-1 downto 0);
  end record example1_reg1_sw2hw_t;

  type example1_reg1_hw2sw_t is record
    we : std_logic;
  --==================================
  -- Field       : field1
  -- Description : Field 1
  -- Width       : 1
  --==================================
    field1 : std_logic_vector(1-1 downto 0);
  --==================================
  -- Field       : field2
  -- Description : Field 2
  -- Width       : 1
  --==================================
    field2 : std_logic_vector(1-1 downto 0);
  end record example1_reg1_hw2sw_t;

  --==================================
  -- Register    : reg2
  -- Description : Register 2
  -- Address     : 0x4
  -- Width       : 16
  -- Sw Access   : rw
  -- Hw Access   : ro
  -- Hw Type     : reg
  --==================================
  type example1_reg2_sw2hw_t is record
    re : std_logic;
    we : std_logic;
  --==================================
  -- Field       : field1
  -- Description : Field 1
  -- Width       : 8
  --==================================
    field1 : std_logic_vector(8-1 downto 0);
  --==================================
  -- Field       : field2
  -- Description : Field 2
  -- Width       : 8
  --==================================
    field2 : std_logic_vector(8-1 downto 0);
  end record example1_reg2_sw2hw_t;

  --==================================
  -- Register    : reg3
  -- Description : Register 3
  -- Address     : 0x8
  -- Width       : 16
  -- Sw Access   : rw
  -- Hw Access   : ro
  -- Hw Type     : ext
  --==================================
  type example1_reg3_sw2hw_t is record
    re : std_logic;
    we : std_logic;
  --==================================
  -- Field       : field1
  -- Description : Field 1
  -- Width       : 8
  --==================================
    field1 : std_logic_vector(8-1 downto 0);
  --==================================
  -- Field       : field2
  -- Description : Field 2
  -- Width       : 8
  --==================================
    field2 : std_logic_vector(8-1 downto 0);
  end record example1_reg3_sw2hw_t;

  --==================================
  -- Register    : fifo_sw2hw
  -- Description : Write Fifo
  -- Address     : 0x10
  -- Width       : 12
  -- Sw Access   : ro
  -- Hw Access   : wo
  -- Hw Type     : fifo
  --==================================
  type example1_fifo_sw2hw_sw2hw_t is record
    ready : std_logic;
    hw2sw_empty : std_logic;
    hw2sw_full  : std_logic;
  end record example1_fifo_sw2hw_sw2hw_t;

  type example1_fifo_sw2hw_hw2sw_t is record
    valid : std_logic;
  --==================================
  -- Field       : field1
  -- Description : Field 1
  -- Width       : 4
  --==================================
    field1 : std_logic_vector(4-1 downto 0);
  --==================================
  -- Field       : field2
  -- Description : Field 2
  -- Width       : 8
  --==================================
    field2 : std_logic_vector(8-1 downto 0);
  end record example1_fifo_sw2hw_hw2sw_t;

  --==================================
  -- Register    : fifo_hw2sw
  -- Description : Read Fifo
  -- Address     : 0x14
  -- Width       : 12
  -- Sw Access   : wo
  -- Hw Access   : ro
  -- Hw Type     : fifo
  --==================================
  type example1_fifo_hw2sw_sw2hw_t is record
    valid : std_logic;
  --==================================
  -- Field       : field1
  -- Description : Field 1
  -- Width       : 4
  --==================================
    field1 : std_logic_vector(4-1 downto 0);
  --==================================
  -- Field       : field2
  -- Description : Field 2
  -- Width       : 8
  --==================================
    field2 : std_logic_vector(8-1 downto 0);
    sw2hw_empty : std_logic;
    sw2hw_full  : std_logic;
  end record example1_fifo_hw2sw_sw2hw_t;

  type example1_fifo_hw2sw_hw2sw_t is record
    ready : std_logic;
  end record example1_fifo_hw2sw_hw2sw_t;

  --==================================
  -- Register    : fifo_bidir
  -- Description : Read/Write Fifo
  -- Address     : 0x18
  -- Width       : 12
  -- Sw Access   : rw
  -- Hw Access   : rw
  -- Hw Type     : fifo
  --==================================
  type example1_fifo_bidir_sw2hw_t is record
    ready : std_logic;
    valid : std_logic;
  --==================================
  -- Field       : field1
  -- Description : Field 1
  -- Width       : 4
  --==================================
    field1 : std_logic_vector(4-1 downto 0);
  --==================================
  -- Field       : field2
  -- Description : Field 2
  -- Width       : 8
  --==================================
    field2 : std_logic_vector(8-1 downto 0);
    sw2hw_empty : std_logic;
    sw2hw_full  : std_logic;
    hw2sw_empty : std_logic;
    hw2sw_full  : std_logic;
  end record example1_fifo_bidir_sw2hw_t;

  type example1_fifo_bidir_hw2sw_t is record
    ready : std_logic;
    valid : std_logic;
  --==================================
  -- Field       : field1
  -- Description : Field 1
  -- Width       : 4
  --==================================
    field1 : std_logic_vector(4-1 downto 0);
  --==================================
  -- Field       : field2
  -- Description : Field 2
  -- Width       : 8
  --==================================
    field2 : std_logic_vector(8-1 downto 0);
  end record example1_fifo_bidir_hw2sw_t;

  ------------------------------------
  -- Structure example1_t
  ------------------------------------
  type example1_sw2hw_t is record
    reg1 : example1_reg1_sw2hw_t;
    reg2 : example1_reg2_sw2hw_t;
    reg3 : example1_reg3_sw2hw_t;
    fifo_sw2hw : example1_fifo_sw2hw_sw2hw_t;
    fifo_hw2sw : example1_fifo_hw2sw_sw2hw_t;
    fifo_bidir : example1_fifo_bidir_sw2hw_t;
  end record example1_sw2hw_t;

  type example1_hw2sw_t is record
    reg1 : example1_reg1_hw2sw_t;
    fifo_sw2hw : example1_fifo_sw2hw_hw2sw_t;
    fifo_hw2sw : example1_fifo_hw2sw_hw2sw_t;
    fifo_bidir : example1_fifo_bidir_hw2sw_t;
  end record example1_hw2sw_t;

  constant example1_ADDR_WIDTH : natural := 5;
  constant example1_DATA_WIDTH : natural := 32;

  ------------------------------------
  -- Component
  ------------------------------------
component example1_registers is
  generic (
    REG1_ENABLE : boolean -- 
  );
  port (
    -- Clock and Reset
    clk_i      : in  std_logic;
    arst_b_i   : in  std_logic;
    -- Bus
    cs_i       : in    std_logic;
    re_i       : in    std_logic;
    we_i       : in    std_logic;
    addr_i     : in    std_logic_vector (5-1 downto 0);
    wdata_i    : in    std_logic_vector (32-1 downto 0);
    rdata_o    : out   std_logic_vector (32-1 downto 0);
    busy_o     : out   std_logic;
    -- CSR
    sw2hw_o    : out example1_sw2hw_t;
    hw2sw_i    : in  example1_hw2sw_t
  );
end component example1_registers;


end package example1_csr_pkg;
