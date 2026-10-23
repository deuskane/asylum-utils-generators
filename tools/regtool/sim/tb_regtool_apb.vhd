-------------------------------------------------------------------------------
-- Title      : tb_regtool_apb
-- Project    : regtool
-------------------------------------------------------------------------------
-- File       : tb_regtool_apb.vhd
-- Author     : Mathieu Rosiere
-- Company    : 
-- Created    : 2026-10-23
-- Platform   : 
-- Standard   : VHDL'08
-------------------------------------------------------------------------------
-- Description:
--  Testbench of the CSR tbcsr generated with the interface "apb" :
--  tb_apb_master -> tbcsr_registers (bridge apb2mem), scenario TEST (tb_regtool_scenario)
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

entity tb_regtool_apb is
  generic (
    TEST       : string := "reset"
    );
end entity tb_regtool_apb;

architecture tb of tb_regtool_apb is

  signal clk        : std_logic;
  signal arst_b     : std_logic;
  signal req        : tb_req_t;
  signal rsp        : tb_rsp_t;
  signal sw2hw      : tbcsr_sw2hw_t;
  signal hw2sw      : tbcsr_hw2sw_t;

  signal psel       : std_logic;
  signal penable    : std_logic;
  signal pwrite     : std_logic;
  signal paddr      : std_logic_vector(TBCSR_ADDR_WIDTH-1 downto 0);
  signal pwdata     : std_logic_vector(TB_DATA_WIDTH-1 downto 0);
  signal prdata     : std_logic_vector(TB_DATA_WIDTH-1 downto 0);
  signal pready     : std_logic;
  signal pslverr    : std_logic;

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

  ins_master : entity work.tb_apb_master
    generic map
    (ADDR_WIDTH => TBCSR_ADDR_WIDTH
    )
    port map
    (clk_i      => clk
    ,req_i      => req
    ,rsp_o      => rsp
    ,psel_o     => psel
    ,penable_o  => penable
    ,pwrite_o   => pwrite
    ,paddr_o    => paddr
    ,pwdata_o   => pwdata
    ,prdata_i   => prdata
    ,pready_i   => pready
    ,pslverr_i  => pslverr
    );

  ins_dut : tbcsr_registers
    port map
    (clk_i           => clk
    ,arst_b_i        => arst_b
    ,s_apb_psel_i    => psel
    ,s_apb_penable_i => penable
    ,s_apb_pwrite_i  => pwrite
    ,s_apb_paddr_i   => paddr
    ,s_apb_pwdata_i  => pwdata
    ,s_apb_prdata_o  => prdata
    ,s_apb_pready_o  => pready
    ,s_apb_pslverr_o => pslverr
    ,sw2hw_o         => sw2hw
    ,hw2sw_i         => hw2sw
    );

end architecture tb;
