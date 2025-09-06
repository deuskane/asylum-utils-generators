-- Generated VHDL Module for example1


library IEEE;
use     IEEE.STD_LOGIC_1164.ALL;
use     IEEE.NUMERIC_STD.ALL;

library work;
use     work.example1_csr_pkg.ALL;
library work;
use     work.csr_pkg.ALL;

--==================================
-- Module      : example1
-- Description : The example 1
-- Width       : 32
--==================================
entity example1_registers is
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
end entity example1_registers;

architecture rtl of example1_registers is

  signal   sig_wcs   : std_logic;
  signal   sig_we    : std_logic;
  signal   sig_waddr : std_logic_vector(addr_i'length-1 downto 0);
  signal   sig_wdata : std_logic_vector(wdata_i'length-1 downto 0);
  signal   sig_wbusy : std_logic;

  signal   sig_rcs   : std_logic;
  signal   sig_re    : std_logic;
  signal   sig_raddr : std_logic_vector(addr_i'length-1 downto 0);
  signal   sig_rdata : std_logic_vector(rdata_o'length-1 downto 0);
  signal   sig_rbusy : std_logic;

  signal   sig_busy  : std_logic;

  constant INIT_reg1 : std_logic_vector(2-1 downto 0) :=
             "0" -- field1
           & "0" -- field2
           ;
  signal   reg1_wcs       : std_logic;
  signal   reg1_we        : std_logic;
  signal   reg1_wdata     : std_logic_vector(32-1 downto 0);
  signal   reg1_wdata_sw  : std_logic_vector(2-1 downto 0);
  signal   reg1_wdata_hw  : std_logic_vector(2-1 downto 0);
  signal   reg1_wbusy     : std_logic;

  signal   reg1_rcs       : std_logic;
  signal   reg1_re        : std_logic;
  signal   reg1_rdata     : std_logic_vector(32-1 downto 0);
  signal   reg1_rdata_sw  : std_logic_vector(2-1 downto 0);
  signal   reg1_rdata_hw  : std_logic_vector(2-1 downto 0);
  signal   reg1_rbusy     : std_logic;

  constant INIT_reg2 : std_logic_vector(16-1 downto 0) :=
             "00000000" -- field1
           & "11111111" -- field2
           ;
  signal   reg2_wcs       : std_logic;
  signal   reg2_we        : std_logic;
  signal   reg2_wdata     : std_logic_vector(32-1 downto 0);
  signal   reg2_wdata_sw  : std_logic_vector(16-1 downto 0);
  signal   reg2_wdata_hw  : std_logic_vector(16-1 downto 0);
  signal   reg2_wbusy     : std_logic;

  signal   reg2_rcs       : std_logic;
  signal   reg2_re        : std_logic;
  signal   reg2_rdata     : std_logic_vector(32-1 downto 0);
  signal   reg2_rdata_sw  : std_logic_vector(16-1 downto 0);
  signal   reg2_rdata_hw  : std_logic_vector(16-1 downto 0);
  signal   reg2_rbusy     : std_logic;

  constant INIT_reg3 : std_logic_vector(16-1 downto 0) :=
             "00000000" -- field1
           & "11111111" -- field2
           ;
  signal   reg3_wcs       : std_logic;
  signal   reg3_we        : std_logic;
  signal   reg3_wdata     : std_logic_vector(32-1 downto 0);
  signal   reg3_wdata_sw  : std_logic_vector(16-1 downto 0);
  signal   reg3_wdata_hw  : std_logic_vector(16-1 downto 0);
  signal   reg3_wbusy     : std_logic;

  signal   reg3_rcs       : std_logic;
  signal   reg3_re        : std_logic;
  signal   reg3_rdata     : std_logic_vector(32-1 downto 0);
  signal   reg3_rdata_sw  : std_logic_vector(16-1 downto 0);
  signal   reg3_rdata_hw  : std_logic_vector(16-1 downto 0);
  signal   reg3_rbusy     : std_logic;

  constant INIT_fifo_sw2hw : std_logic_vector(12-1 downto 0) :=
             "0000" -- field1
           & "00000000" -- field2
           ;
  signal   fifo_sw2hw_wcs       : std_logic;
  signal   fifo_sw2hw_we        : std_logic;
  signal   fifo_sw2hw_wdata     : std_logic_vector(32-1 downto 0);
  signal   fifo_sw2hw_wdata_sw  : std_logic_vector(12-1 downto 0);
  signal   fifo_sw2hw_wdata_hw  : std_logic_vector(12-1 downto 0);
  signal   fifo_sw2hw_wbusy     : std_logic;

  signal   fifo_sw2hw_rcs       : std_logic;
  signal   fifo_sw2hw_re        : std_logic;
  signal   fifo_sw2hw_rdata     : std_logic_vector(32-1 downto 0);
  signal   fifo_sw2hw_rdata_sw  : std_logic_vector(12-1 downto 0);
  signal   fifo_sw2hw_rdata_hw  : std_logic_vector(12-1 downto 0);
  signal   fifo_sw2hw_rbusy     : std_logic;

  constant INIT_fifo_hw2sw : std_logic_vector(12-1 downto 0) :=
             "0000" -- field1
           & "00000000" -- field2
           ;
  signal   fifo_hw2sw_wcs       : std_logic;
  signal   fifo_hw2sw_we        : std_logic;
  signal   fifo_hw2sw_wdata     : std_logic_vector(32-1 downto 0);
  signal   fifo_hw2sw_wdata_sw  : std_logic_vector(12-1 downto 0);
  signal   fifo_hw2sw_wdata_hw  : std_logic_vector(12-1 downto 0);
  signal   fifo_hw2sw_wbusy     : std_logic;

  signal   fifo_hw2sw_rcs       : std_logic;
  signal   fifo_hw2sw_re        : std_logic;
  signal   fifo_hw2sw_rdata     : std_logic_vector(32-1 downto 0);
  signal   fifo_hw2sw_rdata_sw  : std_logic_vector(12-1 downto 0);
  signal   fifo_hw2sw_rdata_hw  : std_logic_vector(12-1 downto 0);
  signal   fifo_hw2sw_rbusy     : std_logic;

  constant INIT_fifo_bidir : std_logic_vector(12-1 downto 0) :=
             "0000" -- field1
           & "00000000" -- field2
           ;
  signal   fifo_bidir_wcs       : std_logic;
  signal   fifo_bidir_we        : std_logic;
  signal   fifo_bidir_wdata     : std_logic_vector(32-1 downto 0);
  signal   fifo_bidir_wdata_sw  : std_logic_vector(12-1 downto 0);
  signal   fifo_bidir_wdata_hw  : std_logic_vector(12-1 downto 0);
  signal   fifo_bidir_wbusy     : std_logic;

  signal   fifo_bidir_rcs       : std_logic;
  signal   fifo_bidir_re        : std_logic;
  signal   fifo_bidir_rdata     : std_logic_vector(32-1 downto 0);
  signal   fifo_bidir_rdata_sw  : std_logic_vector(12-1 downto 0);
  signal   fifo_bidir_rdata_hw  : std_logic_vector(12-1 downto 0);
  signal   fifo_bidir_rbusy     : std_logic;

begin  -- architecture rtl

  -- Interface 
  sig_wcs   <= cs_i;
  sig_we    <= we_i;
  sig_waddr <= addr_i;
  sig_wdata <= wdata_i;

  sig_rcs   <= cs_i;
  sig_re    <= re_i;
  sig_raddr <= addr_i;
  rdata_o <= sig_rdata;
  busy_o <= sig_busy;

  sig_busy  <= sig_wbusy when sig_we = '1' else
               sig_rbusy when sig_re = '1' else
               '0';

  gen_reg1: if (True)
  generate
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


    reg1_rcs     <= '1' when     (sig_raddr(example1_ADDR_WIDTH-1 downto 0) = std_logic_vector(to_unsigned(0,example1_ADDR_WIDTH))) else '0';
    reg1_re      <= sig_rcs and sig_re and reg1_rcs;
    reg1_rdata   <= (
      0 => reg1_rdata_sw(0), -- field1(0)
      2 => reg1_rdata_sw(1), -- field2(0)
      others => '0');

    reg1_wcs     <= '1' when       (sig_waddr(example1_ADDR_WIDTH-1 downto 0) = std_logic_vector(to_unsigned(0,example1_ADDR_WIDTH)))   else '0';
    reg1_we      <= sig_wcs and sig_we and reg1_wcs;
    reg1_wdata   <= sig_wdata;
    reg1_wdata_sw(0 downto 0) <= reg1_wdata(0 downto 0); -- field1
    reg1_wdata_sw(1 downto 1) <= reg1_wdata(2 downto 2); -- field2
    reg1_wdata_hw(0 downto 0) <= hw2sw_i.reg1.field1; -- field1
    reg1_wdata_hw(1 downto 1) <= hw2sw_i.reg1.field2; -- field2
    sw2hw_o.reg1.field1 <= reg1_rdata_hw(0 downto 0); -- field1
    sw2hw_o.reg1.field2 <= reg1_rdata_hw(1 downto 1); -- field2

    ins_reg1 : csr_reg
      generic map
        (WIDTH         => 2
        ,INIT          => INIT_reg1
        ,MODEL         => "rw1c"
        )
      port map
        (clk_i         => clk_i
        ,arst_b_i      => arst_b_i
        ,sw_wd_i       => reg1_wdata_sw
        ,sw_rd_o       => reg1_rdata_sw
        ,sw_we_i       => reg1_we
        ,sw_re_i       => reg1_re
        ,sw_rbusy_o    => reg1_rbusy
        ,sw_wbusy_o    => reg1_wbusy
        ,hw_wd_i       => reg1_wdata_hw
        ,hw_rd_o       => reg1_rdata_hw
        ,hw_we_i       => hw2sw_i.reg1.we
        ,hw_sw_re_o    => sw2hw_o.reg1.re
        ,hw_sw_we_o    => sw2hw_o.reg1.we
        );

  end generate gen_reg1;

  gen_reg1_b: if not (True)
  generate
    reg1_rcs     <= '0';
    reg1_rbusy   <= '0';
    reg1_rdata   <= (others => '0');
    reg1_wcs      <= '0';
    reg1_wbusy    <= '0';
    sw2hw_o.reg1.field1 <= "0";
    sw2hw_o.reg1.field2 <= "0";
    sw2hw_o.reg1.re <= '0';
    sw2hw_o.reg1.we <= '0';
  end generate gen_reg1_b;

  gen_reg2: if (True)
  generate
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


    reg2_rcs     <= '1' when     (sig_raddr(example1_ADDR_WIDTH-1 downto 0) = std_logic_vector(to_unsigned(4,example1_ADDR_WIDTH))) else '0';
    reg2_re      <= sig_rcs and sig_re and reg2_rcs;
    reg2_rdata   <= (
      0 => reg2_rdata_sw(0), -- field1(0)
      1 => reg2_rdata_sw(1), -- field1(1)
      2 => reg2_rdata_sw(2), -- field1(2)
      3 => reg2_rdata_sw(3), -- field1(3)
      4 => reg2_rdata_sw(4), -- field1(4)
      5 => reg2_rdata_sw(5), -- field1(5)
      6 => reg2_rdata_sw(6), -- field1(6)
      7 => reg2_rdata_sw(7), -- field1(7)
      8 => reg2_rdata_sw(8), -- field2(0)
      9 => reg2_rdata_sw(9), -- field2(1)
      10 => reg2_rdata_sw(10), -- field2(2)
      11 => reg2_rdata_sw(11), -- field2(3)
      12 => reg2_rdata_sw(12), -- field2(4)
      13 => reg2_rdata_sw(13), -- field2(5)
      14 => reg2_rdata_sw(14), -- field2(6)
      15 => reg2_rdata_sw(15), -- field2(7)
      others => '0');

    reg2_wcs     <= '1' when       (sig_waddr(example1_ADDR_WIDTH-1 downto 0) = std_logic_vector(to_unsigned(4,example1_ADDR_WIDTH)))   else '0';
    reg2_we      <= sig_wcs and sig_we and reg2_wcs;
    reg2_wdata   <= sig_wdata;
    reg2_wdata_sw(7 downto 0) <= reg2_wdata(7 downto 0); -- field1
    reg2_wdata_sw(15 downto 8) <= reg2_wdata(15 downto 8); -- field2
    sw2hw_o.reg2.field1 <= reg2_rdata_hw(7 downto 0); -- field1
    sw2hw_o.reg2.field2 <= reg2_rdata_hw(15 downto 8); -- field2

    ins_reg2 : csr_reg
      generic map
        (WIDTH         => 16
        ,INIT          => INIT_reg2
        ,MODEL         => "rw"
        )
      port map
        (clk_i         => clk_i
        ,arst_b_i      => arst_b_i
        ,sw_wd_i       => reg2_wdata_sw
        ,sw_rd_o       => reg2_rdata_sw
        ,sw_we_i       => reg2_we
        ,sw_re_i       => reg2_re
        ,sw_rbusy_o    => reg2_rbusy
        ,sw_wbusy_o    => reg2_wbusy
        ,hw_wd_i       => (others => '0')
        ,hw_rd_o       => reg2_rdata_hw
        ,hw_we_i       => '0'
        ,hw_sw_re_o    => sw2hw_o.reg2.re
        ,hw_sw_we_o    => sw2hw_o.reg2.we
        );

  end generate gen_reg2;

  gen_reg2_b: if not (True)
  generate
    reg2_rcs     <= '0';
    reg2_rbusy   <= '0';
    reg2_rdata   <= (others => '0');
    reg2_wcs      <= '0';
    reg2_wbusy    <= '0';
    sw2hw_o.reg2.field1 <= "00000000";
    sw2hw_o.reg2.field2 <= "11111111";
    sw2hw_o.reg2.re <= '0';
    sw2hw_o.reg2.we <= '0';
  end generate gen_reg2_b;

  gen_reg3: if (True)
  generate
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


    reg3_rcs     <= '1' when     (sig_raddr(example1_ADDR_WIDTH-1 downto 0) = std_logic_vector(to_unsigned(8,example1_ADDR_WIDTH))) else '0';
    reg3_re      <= sig_rcs and sig_re and reg3_rcs;
    reg3_rdata   <= (
      0 => reg3_rdata_sw(0), -- field1(0)
      1 => reg3_rdata_sw(1), -- field1(1)
      2 => reg3_rdata_sw(2), -- field1(2)
      3 => reg3_rdata_sw(3), -- field1(3)
      4 => reg3_rdata_sw(4), -- field1(4)
      5 => reg3_rdata_sw(5), -- field1(5)
      6 => reg3_rdata_sw(6), -- field1(6)
      7 => reg3_rdata_sw(7), -- field1(7)
      8 => reg3_rdata_sw(8), -- field2(0)
      9 => reg3_rdata_sw(9), -- field2(1)
      10 => reg3_rdata_sw(10), -- field2(2)
      11 => reg3_rdata_sw(11), -- field2(3)
      12 => reg3_rdata_sw(12), -- field2(4)
      13 => reg3_rdata_sw(13), -- field2(5)
      14 => reg3_rdata_sw(14), -- field2(6)
      15 => reg3_rdata_sw(15), -- field2(7)
      others => '0');

    reg3_wcs     <= '1' when       (sig_waddr(example1_ADDR_WIDTH-1 downto 0) = std_logic_vector(to_unsigned(8,example1_ADDR_WIDTH)))   else '0';
    reg3_we      <= sig_wcs and sig_we and reg3_wcs;
    reg3_wdata   <= sig_wdata;
    reg3_wdata_sw(7 downto 0) <= reg3_wdata(7 downto 0); -- field1
    reg3_wdata_sw(15 downto 8) <= reg3_wdata(15 downto 8); -- field2
    sw2hw_o.reg3.field1 <= reg3_rdata_hw(7 downto 0); -- field1
    sw2hw_o.reg3.field2 <= reg3_rdata_hw(15 downto 8); -- field2

    ins_reg3 : csr_ext
      generic map
        (WIDTH         => 16
        )
      port map
        (clk_i         => clk_i
        ,arst_b_i      => arst_b_i
        ,sw_wd_i       => reg3_wdata_sw
        ,sw_rd_o       => reg3_rdata_sw
        ,sw_we_i       => reg3_we
        ,sw_re_i       => reg3_re
        ,sw_rbusy_o    => reg3_rbusy
        ,sw_wbusy_o    => reg3_wbusy
        ,hw_wd_i       => (others => '0')
        ,hw_rd_o       => reg3_rdata_hw
        ,hw_we_i       => '0'
        ,hw_sw_re_o    => sw2hw_o.reg3.re
        ,hw_sw_we_o    => sw2hw_o.reg3.we
        );

  end generate gen_reg3;

  gen_reg3_b: if not (True)
  generate
    reg3_rcs     <= '0';
    reg3_rbusy   <= '0';
    reg3_rdata   <= (others => '0');
    reg3_wcs      <= '0';
    reg3_wbusy    <= '0';
    sw2hw_o.reg3.field1 <= "00000000";
    sw2hw_o.reg3.field2 <= "11111111";
    sw2hw_o.reg3.re <= '0';
    sw2hw_o.reg3.we <= '0';
  end generate gen_reg3_b;

  gen_fifo_sw2hw: if (True)
  generate
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


    fifo_sw2hw_rcs     <= '1' when     (sig_raddr(example1_ADDR_WIDTH-1 downto 0) = std_logic_vector(to_unsigned(16,example1_ADDR_WIDTH))) else '0';
    fifo_sw2hw_re      <= sig_rcs and sig_re and fifo_sw2hw_rcs;
    fifo_sw2hw_rdata   <= (
      0 => fifo_sw2hw_rdata_sw(0), -- field1(0)
      1 => fifo_sw2hw_rdata_sw(1), -- field1(1)
      2 => fifo_sw2hw_rdata_sw(2), -- field1(2)
      3 => fifo_sw2hw_rdata_sw(3), -- field1(3)
      8 => fifo_sw2hw_rdata_sw(4), -- field2(0)
      9 => fifo_sw2hw_rdata_sw(5), -- field2(1)
      10 => fifo_sw2hw_rdata_sw(6), -- field2(2)
      11 => fifo_sw2hw_rdata_sw(7), -- field2(3)
      12 => fifo_sw2hw_rdata_sw(8), -- field2(4)
      13 => fifo_sw2hw_rdata_sw(9), -- field2(5)
      14 => fifo_sw2hw_rdata_sw(10), -- field2(6)
      15 => fifo_sw2hw_rdata_sw(11), -- field2(7)
      others => '0');

    fifo_sw2hw_wcs      <= '0';
    fifo_sw2hw_we       <= '0';
    fifo_sw2hw_wbusy    <= '0';
    fifo_sw2hw_wdata    <= (others=>'0');
    fifo_sw2hw_wdata_sw <= (others=>'0');
    fifo_sw2hw_wdata_hw(3 downto 0) <= hw2sw_i.fifo_sw2hw.field1; -- field1
    fifo_sw2hw_wdata_hw(11 downto 4) <= hw2sw_i.fifo_sw2hw.field2; -- field2

    ins_fifo_sw2hw : csr_fifo
      generic map
        (WIDTH         => 12
        )
      port map
        (clk_i         => clk_i
        ,arst_b_i      => arst_b_i
        ,sw_wd_i       => fifo_sw2hw_wdata_sw
        ,sw_rd_o       => fifo_sw2hw_rdata_sw
        ,sw_we_i       => fifo_sw2hw_we
        ,sw_re_i       => fifo_sw2hw_re
        ,sw_rbusy_o    => fifo_sw2hw_rbusy
        ,sw_wbusy_o    => fifo_sw2hw_wbusy
        ,hw_tx_valid_i        => hw2sw_i.fifo_sw2hw.valid
        ,hw_tx_ready_o        => sw2hw_o.fifo_sw2hw.ready
        ,hw_tx_data_i         => fifo_sw2hw_wdata_hw
        ,hw_tx_empty_o        => sw2hw_o.fifo_sw2hw.hw2sw_empty
        ,hw_tx_full_o         => sw2hw_o.fifo_sw2hw.hw2sw_full
        ,hw_rx_valid_o        => open
        ,hw_rx_ready_i        => '1'
        ,hw_rx_data_o         => open
        ,hw_rx_empty_o        => open
        ,hw_rx_full_o         => open
        );

  end generate gen_fifo_sw2hw;

  gen_fifo_sw2hw_b: if not (True)
  generate
    fifo_sw2hw_rcs     <= '0';
    fifo_sw2hw_rbusy   <= '0';
    fifo_sw2hw_rdata   <= (others => '0');
    fifo_sw2hw_wcs      <= '0';
    fifo_sw2hw_wbusy    <= '0';
    sw2hw_o.fifo_sw2hw.ready <= '0';
  end generate gen_fifo_sw2hw_b;

  gen_fifo_hw2sw: if (True)
  generate
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

    fifo_hw2sw_wcs     <= '1' when       (sig_waddr(example1_ADDR_WIDTH-1 downto 0) = std_logic_vector(to_unsigned(20,example1_ADDR_WIDTH)))   else '0';
    fifo_hw2sw_we      <= sig_wcs and sig_we and fifo_hw2sw_wcs;
    fifo_hw2sw_wdata   <= sig_wdata;
    fifo_hw2sw_wdata_sw(3 downto 0) <= fifo_hw2sw_wdata(3 downto 0); -- field1
    fifo_hw2sw_wdata_sw(11 downto 4) <= fifo_hw2sw_wdata(15 downto 8); -- field2
    sw2hw_o.fifo_hw2sw.field1 <= fifo_hw2sw_rdata_hw(3 downto 0); -- field1
    sw2hw_o.fifo_hw2sw.field2 <= fifo_hw2sw_rdata_hw(11 downto 4); -- field2

    ins_fifo_hw2sw : csr_fifo
      generic map
        (WIDTH         => 12
        )
      port map
        (clk_i         => clk_i
        ,arst_b_i      => arst_b_i
        ,sw_wd_i       => fifo_hw2sw_wdata_sw
        ,sw_rd_o       => fifo_hw2sw_rdata_sw
        ,sw_we_i       => fifo_hw2sw_we
        ,sw_re_i       => fifo_hw2sw_re
        ,sw_rbusy_o    => fifo_hw2sw_rbusy
        ,sw_wbusy_o    => fifo_hw2sw_wbusy
        ,hw_tx_valid_i        => '0'
        ,hw_tx_ready_o        => open
        ,hw_tx_data_i         => (others => '0')
        ,hw_tx_empty_o        => open
        ,hw_tx_full_o         => open
        ,hw_rx_valid_o        => sw2hw_o.fifo_hw2sw.valid
        ,hw_rx_ready_i        => hw2sw_i.fifo_hw2sw.ready
        ,hw_rx_data_o         => fifo_hw2sw_rdata_hw
        ,hw_rx_empty_o        => sw2hw_o.fifo_hw2sw.sw2hw_empty
        ,hw_rx_full_o         => sw2hw_o.fifo_hw2sw.sw2hw_full
        );

  end generate gen_fifo_hw2sw;

  gen_fifo_hw2sw_b: if not (True)
  generate
    fifo_hw2sw_rcs     <= '0';
    fifo_hw2sw_rbusy   <= '0';
    fifo_hw2sw_rdata   <= (others => '0');
    fifo_hw2sw_wcs      <= '0';
    fifo_hw2sw_wbusy    <= '0';
    sw2hw_o.fifo_hw2sw.field1 <= "0000";
    sw2hw_o.fifo_hw2sw.field2 <= "00000000";
    sw2hw_o.fifo_hw2sw.valid <= '0';
  end generate gen_fifo_hw2sw_b;

  gen_fifo_bidir: if (True)
  generate
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


    fifo_bidir_rcs     <= '1' when     (sig_raddr(example1_ADDR_WIDTH-1 downto 0) = std_logic_vector(to_unsigned(24,example1_ADDR_WIDTH))) else '0';
    fifo_bidir_re      <= sig_rcs and sig_re and fifo_bidir_rcs;
    fifo_bidir_rdata   <= (
      0 => fifo_bidir_rdata_sw(0), -- field1(0)
      1 => fifo_bidir_rdata_sw(1), -- field1(1)
      2 => fifo_bidir_rdata_sw(2), -- field1(2)
      3 => fifo_bidir_rdata_sw(3), -- field1(3)
      8 => fifo_bidir_rdata_sw(4), -- field2(0)
      9 => fifo_bidir_rdata_sw(5), -- field2(1)
      10 => fifo_bidir_rdata_sw(6), -- field2(2)
      11 => fifo_bidir_rdata_sw(7), -- field2(3)
      12 => fifo_bidir_rdata_sw(8), -- field2(4)
      13 => fifo_bidir_rdata_sw(9), -- field2(5)
      14 => fifo_bidir_rdata_sw(10), -- field2(6)
      15 => fifo_bidir_rdata_sw(11), -- field2(7)
      others => '0');

    fifo_bidir_wcs     <= '1' when       (sig_waddr(example1_ADDR_WIDTH-1 downto 0) = std_logic_vector(to_unsigned(24,example1_ADDR_WIDTH)))   else '0';
    fifo_bidir_we      <= sig_wcs and sig_we and fifo_bidir_wcs;
    fifo_bidir_wdata   <= sig_wdata;
    fifo_bidir_wdata_sw(3 downto 0) <= fifo_bidir_wdata(3 downto 0); -- field1
    fifo_bidir_wdata_sw(11 downto 4) <= fifo_bidir_wdata(15 downto 8); -- field2
    fifo_bidir_wdata_hw(3 downto 0) <= hw2sw_i.fifo_bidir.field1; -- field1
    fifo_bidir_wdata_hw(11 downto 4) <= hw2sw_i.fifo_bidir.field2; -- field2
    sw2hw_o.fifo_bidir.field1 <= fifo_bidir_rdata_hw(3 downto 0); -- field1
    sw2hw_o.fifo_bidir.field2 <= fifo_bidir_rdata_hw(11 downto 4); -- field2

    ins_fifo_bidir : csr_fifo
      generic map
        (WIDTH         => 12
        )
      port map
        (clk_i         => clk_i
        ,arst_b_i      => arst_b_i
        ,sw_wd_i       => fifo_bidir_wdata_sw
        ,sw_rd_o       => fifo_bidir_rdata_sw
        ,sw_we_i       => fifo_bidir_we
        ,sw_re_i       => fifo_bidir_re
        ,sw_rbusy_o    => fifo_bidir_rbusy
        ,sw_wbusy_o    => fifo_bidir_wbusy
        ,hw_tx_valid_i        => hw2sw_i.fifo_bidir.valid
        ,hw_tx_ready_o        => sw2hw_o.fifo_bidir.ready
        ,hw_tx_data_i         => fifo_bidir_wdata_hw
        ,hw_tx_empty_o        => sw2hw_o.fifo_bidir.hw2sw_empty
        ,hw_tx_full_o         => sw2hw_o.fifo_bidir.hw2sw_full
        ,hw_rx_valid_o        => sw2hw_o.fifo_bidir.valid
        ,hw_rx_ready_i        => hw2sw_i.fifo_bidir.ready
        ,hw_rx_data_o         => fifo_bidir_rdata_hw
        ,hw_rx_empty_o        => sw2hw_o.fifo_bidir.sw2hw_empty
        ,hw_rx_full_o         => sw2hw_o.fifo_bidir.sw2hw_full
        );

  end generate gen_fifo_bidir;

  gen_fifo_bidir_b: if not (True)
  generate
    fifo_bidir_rcs     <= '0';
    fifo_bidir_rbusy   <= '0';
    fifo_bidir_rdata   <= (others => '0');
    fifo_bidir_wcs      <= '0';
    fifo_bidir_wbusy    <= '0';
    sw2hw_o.fifo_bidir.field1 <= "0000";
    sw2hw_o.fifo_bidir.field2 <= "00000000";
    sw2hw_o.fifo_bidir.ready <= '0';
    sw2hw_o.fifo_bidir.valid <= '0';
  end generate gen_fifo_bidir_b;

  sig_wbusy <= 
    reg1_wbusy when reg1_wcs = '1' else
    reg2_wbusy when reg2_wcs = '1' else
    reg3_wbusy when reg3_wcs = '1' else
    fifo_sw2hw_wbusy when fifo_sw2hw_wcs = '1' else
    fifo_hw2sw_wbusy when fifo_hw2sw_wcs = '1' else
    fifo_bidir_wbusy when fifo_bidir_wcs = '1' else
    '0'; -- Bad Address, no busy
  sig_rbusy <= 
    reg1_rbusy when reg1_rcs = '1' else
    reg2_rbusy when reg2_rcs = '1' else
    reg3_rbusy when reg3_rcs = '1' else
    fifo_sw2hw_rbusy when fifo_sw2hw_rcs = '1' else
    fifo_hw2sw_rbusy when fifo_hw2sw_rcs = '1' else
    fifo_bidir_rbusy when fifo_bidir_rcs = '1' else
    '0'; -- Bad Address, no busy
  sig_rdata <= 
    reg1_rdata when reg1_rcs = '1' else
    reg2_rdata when reg2_rcs = '1' else
    reg3_rdata when reg3_rcs = '1' else
    fifo_sw2hw_rdata when fifo_sw2hw_rcs = '1' else
    fifo_hw2sw_rdata when fifo_hw2sw_rcs = '1' else
    fifo_bidir_rdata when fifo_bidir_rcs = '1' else
    (others => '0'); -- Bad Address, return 0
end architecture rtl;
