-- Generated VHDL Module for example1


library IEEE;
use     IEEE.STD_LOGIC_1164.ALL;
use     IEEE.NUMERIC_STD.ALL;

library work;
use     work.example1_csr_pkg.ALL;

--==================================
-- Module      : example1
-- Description : The example 1
-- Width       : 32
--==================================
entity example1_registers is
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
end entity example1_registers;

architecture rtl of example1_registers is

  constant SIZE_ADDR : integer := 5;
  signal   reg1_wcs   : std_logic;
  signal   reg1_rcs   : std_logic;
  signal   reg1_we    : std_logic;
  signal   reg1_re    : std_logic;
  signal   reg1_rdata : std_logic_vector(32-1 downto 0);
  signal   reg1_wdata : std_logic_vector(32-1 downto 0);
  signal   reg1_rbusy : std_logic;
  signal   reg1_field1_rdata : std_logic_vector(0 downto 0);
  signal   reg1_field2_rdata : std_logic_vector(2 downto 2);

  signal   reg2_wcs   : std_logic;
  signal   reg2_rcs   : std_logic;
  signal   reg2_we    : std_logic;
  signal   reg2_re    : std_logic;
  signal   reg2_rdata : std_logic_vector(32-1 downto 0);
  signal   reg2_wdata : std_logic_vector(32-1 downto 0);
  signal   reg2_rbusy : std_logic;
  signal   reg2_field1_rdata : std_logic_vector(7 downto 0);
  signal   reg2_field2_rdata : std_logic_vector(15 downto 8);

  signal   reg3_wcs   : std_logic;
  signal   reg3_rcs   : std_logic;
  signal   reg3_we    : std_logic;
  signal   reg3_re    : std_logic;
  signal   reg3_rdata : std_logic_vector(32-1 downto 0);
  signal   reg3_wdata : std_logic_vector(32-1 downto 0);
  signal   reg3_rbusy : std_logic;
  signal   reg3_field1_rdata : std_logic_vector(7 downto 0);
  signal   reg3_field2_rdata : std_logic_vector(15 downto 8);

  signal   fifo_sw2hw_wcs   : std_logic;
  signal   fifo_sw2hw_rcs   : std_logic;
  signal   fifo_sw2hw_we    : std_logic;
  signal   fifo_sw2hw_re    : std_logic;
  signal   fifo_sw2hw_rdata : std_logic_vector(32-1 downto 0);
  signal   fifo_sw2hw_wdata : std_logic_vector(32-1 downto 0);
  signal   fifo_sw2hw_rbusy : std_logic;
  signal   fifo_sw2hw_field1_rdata : std_logic_vector(3 downto 0);
  signal   fifo_sw2hw_field2_rdata : std_logic_vector(15 downto 8);

  signal   fifo_hw2sw_wcs   : std_logic;
  signal   fifo_hw2sw_rcs   : std_logic;
  signal   fifo_hw2sw_we    : std_logic;
  signal   fifo_hw2sw_re    : std_logic;
  signal   fifo_hw2sw_rdata : std_logic_vector(32-1 downto 0);
  signal   fifo_hw2sw_wdata : std_logic_vector(32-1 downto 0);
  signal   fifo_hw2sw_rbusy : std_logic;
  signal   fifo_hw2sw_field1_rdata : std_logic_vector(3 downto 0);
  signal   fifo_hw2sw_field2_rdata : std_logic_vector(15 downto 8);

  signal   fifo_bidir_wcs   : std_logic;
  signal   fifo_bidir_rcs   : std_logic;
  signal   fifo_bidir_we    : std_logic;
  signal   fifo_bidir_re    : std_logic;
  signal   fifo_bidir_rdata : std_logic_vector(32-1 downto 0);
  signal   fifo_bidir_wdata : std_logic_vector(32-1 downto 0);
  signal   fifo_bidir_rbusy : std_logic;
  signal   fifo_bidir_field1_rdata : std_logic_vector(3 downto 0);
  signal   fifo_bidir_field2_rdata : std_logic_vector(15 downto 8);

begin  -- architecture rtl

  --==================================
  -- Register    : reg1
  -- Description : Register 1
  -- Address     : 0x0
  -- Width       : 2
  -- Sw Access   : rw1c
  -- Hw Access   : rw
  -- Hw Type     : reg
  --==================================
  --==================================
  -- Field       : field1
  -- Description : Field 1
  -- Width       : 1
  --==================================

  --==================================
  -- Field       : field2
  -- Description : Field 2
  -- Width       : 1
  --==================================


  reg1_rcs     <= '1' when     (addr_i = std_logic_vector(to_unsigned(0,SIZE_ADDR))) else '0';
  reg1_re      <= cs_i and reg1_rcs and re_i;
  reg1_rdata   <= (
    0 => reg1_field1_rdata(0),
    2 => reg1_field2_rdata(2),
    others => '0') when reg1_rcs = '1' else (others => '0');
  reg1_rbusy   <= '0';

  reg1_wcs     <= '1' when     (addr_i = std_logic_vector(to_unsigned(0,SIZE_ADDR))) else '0';
  reg1_we      <= cs_i and reg1_wcs and we_i;
  reg1_wdata   <= wdata_i;

  ins_reg1 : entity work.csr_reg(rtl)
    generic map
      (WIDTH         => 2
      ,INIT          => "0"
                       &"0"
      ,MODEL         => "rw1c"
      )
    port map
      (clk_i         => clk_i
      ,arst_b_i      => arst_b_i
      ,sw_wd_i       => reg1_wdata(0 downto 0)
                       &reg1_wdata(2 downto 2)
      ,sw_rd_o       => reg1_field1_rdata
                       &reg1_field2_rdata
      ,sw_we_i       => reg1_we
      ,sw_re_i       => reg1_re
      ,hw_wd_i       => hw2sw_i.reg1.field1
                       &hw2sw_i.reg1.field2
      ,hw_rd_o       => sw2hw_o.reg1.field1
                       &sw2hw_o.reg1.field2
      ,hw_we_i       => hw2sw_i.reg1.we
      ,hw_sw_re_o    => sw2hw_o.reg1.re
      ,hw_sw_we_o    => sw2hw_o.reg1.we
      );

  --==================================
  -- Register    : reg2
  -- Description : Register 2
  -- Address     : 0x4
  -- Width       : 16
  -- Sw Access   : rw
  -- Hw Access   : ro
  -- Hw Type     : reg
  --==================================
  --==================================
  -- Field       : field1
  -- Description : Field 1
  -- Width       : 8
  --==================================

  --==================================
  -- Field       : field2
  -- Description : Field 2
  -- Width       : 8
  --==================================


  reg2_rcs     <= '1' when     (addr_i = std_logic_vector(to_unsigned(4,SIZE_ADDR))) else '0';
  reg2_re      <= cs_i and reg2_rcs and re_i;
  reg2_rdata   <= (
    7 => reg2_field1_rdata(7),
    6 => reg2_field1_rdata(6),
    5 => reg2_field1_rdata(5),
    4 => reg2_field1_rdata(4),
    3 => reg2_field1_rdata(3),
    2 => reg2_field1_rdata(2),
    1 => reg2_field1_rdata(1),
    0 => reg2_field1_rdata(0),
    15 => reg2_field2_rdata(15),
    14 => reg2_field2_rdata(14),
    13 => reg2_field2_rdata(13),
    12 => reg2_field2_rdata(12),
    11 => reg2_field2_rdata(11),
    10 => reg2_field2_rdata(10),
    9 => reg2_field2_rdata(9),
    8 => reg2_field2_rdata(8),
    others => '0') when reg2_rcs = '1' else (others => '0');
  reg2_rbusy   <= '0';

  reg2_wcs     <= '1' when     (addr_i = std_logic_vector(to_unsigned(4,SIZE_ADDR))) else '0';
  reg2_we      <= cs_i and reg2_wcs and we_i;
  reg2_wdata   <= wdata_i;

  ins_reg2 : entity work.csr_reg(rtl)
    generic map
      (WIDTH         => 16
      ,INIT          => "00000000"
                       &"11111111"
      ,MODEL         => "rw"
      )
    port map
      (clk_i         => clk_i
      ,arst_b_i      => arst_b_i
      ,sw_wd_i       => reg2_wdata(7 downto 0)
                       &reg2_wdata(15 downto 8)
      ,sw_rd_o       => reg2_field1_rdata
                       &reg2_field2_rdata
      ,sw_we_i       => reg2_we
      ,sw_re_i       => reg2_re
      ,hw_wd_i       => (others => '0')
      ,hw_rd_o       => sw2hw_o.reg2.field1
                       &sw2hw_o.reg2.field2
      ,hw_we_i       => '0'
      ,hw_sw_re_o    => sw2hw_o.reg2.re
      ,hw_sw_we_o    => sw2hw_o.reg2.we
      );

  --==================================
  -- Register    : reg3
  -- Description : Register 3
  -- Address     : 0x8
  -- Width       : 16
  -- Sw Access   : rw
  -- Hw Access   : ro
  -- Hw Type     : ext
  --==================================
  --==================================
  -- Field       : field1
  -- Description : Field 1
  -- Width       : 8
  --==================================

  --==================================
  -- Field       : field2
  -- Description : Field 2
  -- Width       : 8
  --==================================


  reg3_rcs     <= '1' when     (addr_i = std_logic_vector(to_unsigned(8,SIZE_ADDR))) else '0';
  reg3_re      <= cs_i and reg3_rcs and re_i;
  reg3_rdata   <= (
    7 => reg3_field1_rdata(7),
    6 => reg3_field1_rdata(6),
    5 => reg3_field1_rdata(5),
    4 => reg3_field1_rdata(4),
    3 => reg3_field1_rdata(3),
    2 => reg3_field1_rdata(2),
    1 => reg3_field1_rdata(1),
    0 => reg3_field1_rdata(0),
    15 => reg3_field2_rdata(15),
    14 => reg3_field2_rdata(14),
    13 => reg3_field2_rdata(13),
    12 => reg3_field2_rdata(12),
    11 => reg3_field2_rdata(11),
    10 => reg3_field2_rdata(10),
    9 => reg3_field2_rdata(9),
    8 => reg3_field2_rdata(8),
    others => '0') when reg3_rcs = '1' else (others => '0');
  reg3_rbusy   <= '0';

  reg3_wcs     <= '1' when     (addr_i = std_logic_vector(to_unsigned(8,SIZE_ADDR))) else '0';
  reg3_we      <= cs_i and reg3_wcs and we_i;
  reg3_wdata   <= wdata_i;

  ins_reg3 : entity work.csr_ext(rtl)
    generic map
      (WIDTH         => 16
      )
    port map
      (clk_i         => clk_i
      ,arst_b_i      => arst_b_i
      ,sw_wd_i       => reg3_wdata(7 downto 0)
                       &reg3_wdata(15 downto 8)
      ,sw_rd_o       => reg3_field1_rdata
                       &reg3_field2_rdata
      ,sw_we_i       => reg3_we
      ,sw_re_i       => reg3_re
      ,hw_wd_i       => (others => '0')
      ,hw_rd_o       => sw2hw_o.reg3.field1
                       &sw2hw_o.reg3.field2
      ,hw_we_i       => '0'
      ,hw_sw_re_o    => sw2hw_o.reg3.re
      ,hw_sw_we_o    => sw2hw_o.reg3.we
      );

  --==================================
  -- Register    : fifo_sw2hw
  -- Description : Write Fifo
  -- Address     : 0x10
  -- Width       : 12
  -- Sw Access   : ro
  -- Hw Access   : wo
  -- Hw Type     : fifo
  --==================================
  --==================================
  -- Field       : field1
  -- Description : Field 1
  -- Width       : 4
  --==================================

  --==================================
  -- Field       : field2
  -- Description : Field 2
  -- Width       : 8
  --==================================


  fifo_sw2hw_rcs     <= '1' when     (addr_i = std_logic_vector(to_unsigned(16,SIZE_ADDR))) else '0';
  fifo_sw2hw_re      <= cs_i and fifo_sw2hw_rcs and re_i;
  fifo_sw2hw_rdata   <= (
    3 => fifo_sw2hw_field1_rdata(3),
    2 => fifo_sw2hw_field1_rdata(2),
    1 => fifo_sw2hw_field1_rdata(1),
    0 => fifo_sw2hw_field1_rdata(0),
    15 => fifo_sw2hw_field2_rdata(15),
    14 => fifo_sw2hw_field2_rdata(14),
    13 => fifo_sw2hw_field2_rdata(13),
    12 => fifo_sw2hw_field2_rdata(12),
    11 => fifo_sw2hw_field2_rdata(11),
    10 => fifo_sw2hw_field2_rdata(10),
    9 => fifo_sw2hw_field2_rdata(9),
    8 => fifo_sw2hw_field2_rdata(8),
    others => '0') when fifo_sw2hw_rcs = '1' else (others => '0');
  fifo_sw2hw_rbusy   <= '0';

  fifo_sw2hw_wcs     <= '0';
  fifo_sw2hw_we      <= '0';
  fifo_sw2hw_wdata   <= (others=>'0');

  ins_fifo_sw2hw : entity work.csr_fifo(rtl)
    generic map
      (WIDTH         => 12
      )
    port map
      (clk_i         => clk_i
      ,arst_b_i      => arst_b_i
      ,sw_wd_i       => fifo_sw2hw_wdata(3 downto 0)
                       &fifo_sw2hw_wdata(15 downto 8)
      ,sw_rd_o       => fifo_sw2hw_field1_rdata
                       &fifo_sw2hw_field2_rdata
      ,sw_we_i       => fifo_sw2hw_we
      ,sw_re_i       => fifo_sw2hw_re
      ,hw_tx_valid_i => hw2sw_i.fifo_sw2hw.valid
      ,hw_tx_ready_o => sw2hw_o.fifo_sw2hw.ready
      ,hw_tx_data_i  => hw2sw_i.fifo_sw2hw.field1
                       &hw2sw_i.fifo_sw2hw.field2
      ,hw_rx_valid_o => open
      ,hw_rx_ready_i => '1'
      ,hw_rx_data_o  => open
      );

  --==================================
  -- Register    : fifo_hw2sw
  -- Description : Read Fifo
  -- Address     : 0x14
  -- Width       : 12
  -- Sw Access   : wo
  -- Hw Access   : ro
  -- Hw Type     : fifo
  --==================================
  --==================================
  -- Field       : field1
  -- Description : Field 1
  -- Width       : 4
  --==================================

  --==================================
  -- Field       : field2
  -- Description : Field 2
  -- Width       : 8
  --==================================


  fifo_hw2sw_rcs     <= '0';
  fifo_hw2sw_re      <= '0';
  fifo_hw2sw_rdata   <= (others=>'0');
  fifo_hw2sw_rbusy   <= '0';

  fifo_hw2sw_wcs     <= '1' when     (addr_i = std_logic_vector(to_unsigned(20,SIZE_ADDR))) else '0';
  fifo_hw2sw_we      <= cs_i and fifo_hw2sw_wcs and we_i;
  fifo_hw2sw_wdata   <= wdata_i;

  ins_fifo_hw2sw : entity work.csr_fifo(rtl)
    generic map
      (WIDTH         => 12
      )
    port map
      (clk_i         => clk_i
      ,arst_b_i      => arst_b_i
      ,sw_wd_i       => fifo_hw2sw_wdata(3 downto 0)
                       &fifo_hw2sw_wdata(15 downto 8)
      ,sw_rd_o       => fifo_hw2sw_field1_rdata
                       &fifo_hw2sw_field2_rdata
      ,sw_we_i       => fifo_hw2sw_we
      ,sw_re_i       => fifo_hw2sw_re
      ,hw_tx_valid_i => '0'
      ,hw_tx_ready_o => open
      ,hw_tx_data_i  => (others => '0')
      ,hw_rx_valid_o => sw2hw_o.fifo_hw2sw.valid
      ,hw_rx_ready_i => hw2sw_i.fifo_hw2sw.ready
      ,hw_rx_data_o  => sw2hw_o.fifo_hw2sw.field1
                       &sw2hw_o.fifo_hw2sw.field2
      );

  --==================================
  -- Register    : fifo_bidir
  -- Description : Read/Write Fifo
  -- Address     : 0x18
  -- Width       : 12
  -- Sw Access   : rw
  -- Hw Access   : rw
  -- Hw Type     : fifo
  --==================================
  --==================================
  -- Field       : field1
  -- Description : Field 1
  -- Width       : 4
  --==================================

  --==================================
  -- Field       : field2
  -- Description : Field 2
  -- Width       : 8
  --==================================


  fifo_bidir_rcs     <= '1' when     (addr_i = std_logic_vector(to_unsigned(24,SIZE_ADDR))) else '0';
  fifo_bidir_re      <= cs_i and fifo_bidir_rcs and re_i;
  fifo_bidir_rdata   <= (
    3 => fifo_bidir_field1_rdata(3),
    2 => fifo_bidir_field1_rdata(2),
    1 => fifo_bidir_field1_rdata(1),
    0 => fifo_bidir_field1_rdata(0),
    15 => fifo_bidir_field2_rdata(15),
    14 => fifo_bidir_field2_rdata(14),
    13 => fifo_bidir_field2_rdata(13),
    12 => fifo_bidir_field2_rdata(12),
    11 => fifo_bidir_field2_rdata(11),
    10 => fifo_bidir_field2_rdata(10),
    9 => fifo_bidir_field2_rdata(9),
    8 => fifo_bidir_field2_rdata(8),
    others => '0') when fifo_bidir_rcs = '1' else (others => '0');
  fifo_bidir_rbusy   <= '0';

  fifo_bidir_wcs     <= '1' when     (addr_i = std_logic_vector(to_unsigned(24,SIZE_ADDR))) else '0';
  fifo_bidir_we      <= cs_i and fifo_bidir_wcs and we_i;
  fifo_bidir_wdata   <= wdata_i;

  ins_fifo_bidir : entity work.csr_fifo(rtl)
    generic map
      (WIDTH         => 12
      )
    port map
      (clk_i         => clk_i
      ,arst_b_i      => arst_b_i
      ,sw_wd_i       => fifo_bidir_wdata(3 downto 0)
                       &fifo_bidir_wdata(15 downto 8)
      ,sw_rd_o       => fifo_bidir_field1_rdata
                       &fifo_bidir_field2_rdata
      ,sw_we_i       => fifo_bidir_we
      ,sw_re_i       => fifo_bidir_re
      ,hw_tx_valid_i => hw2sw_i.fifo_bidir.valid
      ,hw_tx_ready_o => sw2hw_o.fifo_bidir.ready
      ,hw_tx_data_i  => hw2sw_i.fifo_bidir.field1
                       &hw2sw_i.fifo_bidir.field2
      ,hw_rx_valid_o => sw2hw_o.fifo_bidir.valid
      ,hw_rx_ready_i => hw2sw_i.fifo_bidir.ready
      ,hw_rx_data_o  => sw2hw_o.fifo_bidir.field1
                       &sw2hw_o.fifo_bidir.field2
      );

  busy_o  <= 
    reg1_rbusy or
    reg2_rbusy or
    reg3_rbusy or
    fifo_sw2hw_rbusy or
    fifo_hw2sw_rbusy or
    fifo_bidir_rbusy;
  rdata_o <= 
    reg1_rdata or
    reg2_rdata or
    reg3_rdata or
    fifo_sw2hw_rdata or
    fifo_hw2sw_rdata or
    fifo_bidir_rdata;
end architecture rtl;
