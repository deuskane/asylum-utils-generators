-- Generated VHDL Module for example2


library IEEE;
use     IEEE.STD_LOGIC_1164.ALL;
use     IEEE.NUMERIC_STD.ALL;

library asylum;
use     asylum.example2_csr_pkg.ALL;
library asylum;
use     asylum.csr_pkg.ALL;

--==================================
-- Module      : example2
-- Description : test
-- Width       : 32
--==================================
entity example2_registers is
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
   ;sw2hw_o    : out example2_sw2hw_t
  );
end entity example2_registers;

architecture rtl of example2_registers is

  signal   sig_wcs   : std_logic;
  signal   sig_we    : std_logic;
  signal   sig_waddr : unsigned(example2_ADDR_WIDTH-1 downto 0);
  signal   sig_wdata : std_logic_vector(wdata_i'length-1 downto 0);
  signal   sig_wbusy : std_logic;

  signal   sig_rcs   : std_logic;
  signal   sig_re    : std_logic;
  signal   sig_raddr : unsigned(example2_ADDR_WIDTH-1 downto 0);
  signal   sig_rdata : std_logic_vector(rdata_o'length-1 downto 0);
  signal   sig_rbusy : std_logic;

  signal   sig_busy  : std_logic;

  function INIT_regA
    return std_logic_vector is
    variable tmp : std_logic_vector(16-1 downto 0);
  begin  -- function INIT_regA
    tmp(7 downto 0) := "00000000"; -- a
    tmp(15 downto 8) := "00000000"; -- b
    return tmp;
  end function INIT_regA;

  signal   regA_wcs       : std_logic;
  signal   regA_we        : std_logic;
  signal   regA_wdata     : std_logic_vector(32-1 downto 0);
  signal   regA_wdata_sw  : std_logic_vector(16-1 downto 0);
  signal   regA_wbusy     : std_logic;

  signal   regA_rcs       : std_logic;
  signal   regA_re        : std_logic;
  signal   regA_rdata     : std_logic_vector(32-1 downto 0);
  signal   regA_rdata_sw  : std_logic_vector(16-1 downto 0);
  signal   regA_rdata_hw  : std_logic_vector(16-1 downto 0);
  signal   regA_rbusy     : std_logic;

begin  -- architecture rtl

  -- Interface 
  sig_wcs   <= cs_i;
  sig_we    <= we_i;
  sig_waddr <= unsigned(addr_i(example2_ADDR_WIDTH-1 downto 0));
  sig_wdata <= wdata_i;

  sig_rcs   <= cs_i;
  sig_re    <= re_i;
  sig_raddr <= unsigned(addr_i(example2_ADDR_WIDTH-1 downto 0));
  rdata_o <= sig_rdata;
  busy_o <= sig_busy;

  sig_busy  <= sig_wbusy when sig_we = '1' else
               sig_rbusy when sig_re = '1' else
               '0';

  gen_regA: if (True)
  generate
  --==================================
  -- Register    : regA
  -- Description : A
  -- Address     : 0x0
  -- Width       : 16
  -- Sw Access   : rw
  -- Hw Access   : ro
  -- Hw Type     : reg
  --==================================
  --==================================
  -- Field       : a
  -- Description : a
  -- Width       : 8
  --==================================

  --==================================
  -- Field       : b
  -- Description : b
  -- Width       : 8
  --==================================


    regA_rcs     <= '1' when (sig_raddr = example2_REGA) else '0';
    regA_re      <= sig_rcs and sig_re and regA_rcs;
    regA_rdata   <= (
       0 => regA_rdata_sw(0) -- a(0)
      ,1 => regA_rdata_sw(1) -- a(1)
      ,2 => regA_rdata_sw(2) -- a(2)
      ,3 => regA_rdata_sw(3) -- a(3)
      ,4 => regA_rdata_sw(4) -- a(4)
      ,5 => regA_rdata_sw(5) -- a(5)
      ,6 => regA_rdata_sw(6) -- a(6)
      ,7 => regA_rdata_sw(7) -- a(7)
      ,8 => regA_rdata_sw(8) -- b(0)
      ,9 => regA_rdata_sw(9) -- b(1)
      ,10 => regA_rdata_sw(10) -- b(2)
      ,11 => regA_rdata_sw(11) -- b(3)
      ,12 => regA_rdata_sw(12) -- b(4)
      ,13 => regA_rdata_sw(13) -- b(5)
      ,14 => regA_rdata_sw(14) -- b(6)
      ,15 => regA_rdata_sw(15) -- b(7)
      ,others => '0'
      );

    regA_wcs     <= '1' when       (sig_waddr = example2_REGA)   else '0';
    regA_we      <= sig_wcs and sig_we and regA_wcs;
    regA_wdata   <= sig_wdata;
    regA_wdata_sw(7 downto 0) <= regA_wdata(7 downto 0); -- a
    regA_wdata_sw(15 downto 8) <= regA_wdata(15 downto 8); -- b
    sw2hw_o.regA.a <= regA_rdata_hw(7 downto 0); -- a
    sw2hw_o.regA.b <= regA_rdata_hw(15 downto 8); -- b

    ins_regA : csr_reg
      generic map
        (WIDTH         => 16
        ,INIT          => INIT_regA
        ,MODEL         => "rw"
        )
      port map
        (clk_i         => clk_i
        ,arst_b_i      => arst_b_i
        ,sw_wd_i       => regA_wdata_sw
        ,sw_rd_o       => regA_rdata_sw
        ,sw_we_i       => regA_we
        ,sw_re_i       => regA_re
        ,sw_rbusy_o    => regA_rbusy
        ,sw_wbusy_o    => regA_wbusy
        ,hw_wd_i       => (others => '0')
        ,hw_rd_o       => regA_rdata_hw
        ,hw_we_i       => '0'
        ,hw_sw_re_o    => sw2hw_o.regA.re
        ,hw_sw_we_o    => sw2hw_o.regA.we
        );

  end generate gen_regA;

  gen_regA_b: if not (True)
  generate
    regA_rcs     <= '0';
    regA_rbusy   <= '0';
    regA_rdata   <= (others => '0');
    regA_wcs      <= '0';
    regA_wbusy    <= '0';
    sw2hw_o.regA.a <= "00000000";
    sw2hw_o.regA.b <= "00000000";
    sw2hw_o.regA.re <= '0';
    sw2hw_o.regA.we <= '0';
  end generate gen_regA_b;

  sig_wbusy <= 
    regA_wbusy when regA_wcs = '1' else
    '0'; -- Bad Address, no busy
  sig_rbusy <= 
    regA_rbusy when regA_rcs = '1' else
    '0'; -- Bad Address, no busy
  sig_rdata <= 
    regA_rdata when regA_rcs = '1' else
    (others => '0'); -- Bad Address, return 0
end architecture rtl;
