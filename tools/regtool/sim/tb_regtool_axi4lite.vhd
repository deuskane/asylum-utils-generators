-------------------------------------------------------------------------------
-- Title      : tb_regtool_axi4lite
-- Project    : regtool
-------------------------------------------------------------------------------
-- File       : tb_regtool_axi4lite.vhd
-- Author     : Mathieu Rosiere
-- Company    : 
-- Created    : 2026-10-23
-- Platform   : 
-- Standard   : VHDL'08
-------------------------------------------------------------------------------
-- Description:
--  Testbench of the CSR tbcsr generated with the interface "axi4lite" :
--  tb_axi4lite_master -> tbcsr_registers (bridge axi4lite2mem), scenario TEST (tb_regtool_scenario)
-------------------------------------------------------------------------------
-- Copyright (c) 2026 
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author   Description
-- 2026-10-23  1.0      mrosiere Created
-------------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;

library asylum;
use     asylum.tbcsr_csr_pkg.all;
use     asylum.tb_regtool_pkg.all;

entity tb_regtool_axi4lite is
  generic (
    TEST       : string := "reset"
    );
end entity tb_regtool_axi4lite;

architecture tb of tb_regtool_axi4lite is

  signal clk        : std_logic;
  signal arst_b     : std_logic;
  signal req        : tb_req_t;
  signal rsp        : tb_rsp_t;
  signal sw2hw      : tbcsr_sw2hw_t;
  signal hw2sw      : tbcsr_hw2sw_t;

  signal awvalid    : std_logic;
  signal awready    : std_logic;
  signal awaddr     : std_logic_vector(TBCSR_ADDR_WIDTH-1 downto 0);
  signal wvalid     : std_logic;
  signal wready     : std_logic;
  signal wdata      : std_logic_vector(TB_DATA_WIDTH-1 downto 0);
  signal wstrb      : std_logic_vector(TB_DATA_WIDTH/8-1 downto 0);
  signal bvalid     : std_logic;
  signal bready     : std_logic;
  signal bresp      : std_logic_vector(1 downto 0);
  signal arvalid    : std_logic;
  signal arready    : std_logic;
  signal araddr     : std_logic_vector(TBCSR_ADDR_WIDTH-1 downto 0);
  signal rvalid     : std_logic;
  signal rready     : std_logic;
  signal rdata      : std_logic_vector(TB_DATA_WIDTH-1 downto 0);
  signal rresp      : std_logic_vector(1 downto 0);

begin  -- architecture tb

  ins_scenario : entity work.tb_regtool_scenario
    generic map
    (TEST       => TEST
    )
    port map
    (clk_o      => clk
    ,arst_b_o   => arst_b
    ,req_o      => req
    ,rsp_i      => rsp
    ,sw2hw_i    => sw2hw
    ,hw2sw_o    => hw2sw
    );

  ins_master : entity work.tb_axi4lite_master
    generic map
    (ADDR_WIDTH => TBCSR_ADDR_WIDTH
    )
    port map
    (clk_i      => clk
    ,req_i      => req
    ,rsp_o      => rsp
    ,awvalid_o  => awvalid
    ,awready_i  => awready
    ,awaddr_o   => awaddr
    ,wvalid_o   => wvalid
    ,wready_i   => wready
    ,wdata_o    => wdata
    ,wstrb_o    => wstrb
    ,bvalid_i   => bvalid
    ,bready_o   => bready
    ,bresp_i    => bresp
    ,arvalid_o  => arvalid
    ,arready_i  => arready
    ,araddr_o   => araddr
    ,rvalid_i   => rvalid
    ,rready_o   => rready
    ,rdata_i    => rdata
    ,rresp_i    => rresp
    );

  ins_dut : tbcsr_registers
    port map
    (clk_i           => clk
    ,arst_b_i        => arst_b
    ,s_axi_awvalid_i => awvalid
    ,s_axi_awready_o => awready
    ,s_axi_awaddr_i  => awaddr
    ,s_axi_wvalid_i  => wvalid
    ,s_axi_wready_o  => wready
    ,s_axi_wdata_i   => wdata
    ,s_axi_wstrb_i   => wstrb
    ,s_axi_bvalid_o  => bvalid
    ,s_axi_bready_i  => bready
    ,s_axi_bresp_o   => bresp
    ,s_axi_arvalid_i => arvalid
    ,s_axi_arready_o => arready
    ,s_axi_araddr_i  => araddr
    ,s_axi_rvalid_o  => rvalid
    ,s_axi_rready_i  => rready
    ,s_axi_rdata_o   => rdata
    ,s_axi_rresp_o   => rresp
    ,sw2hw_o         => sw2hw
    ,hw2sw_i         => hw2sw
    );

end architecture tb;
