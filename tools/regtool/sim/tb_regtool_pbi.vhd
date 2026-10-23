-------------------------------------------------------------------------------
-- Title      : tb_regtool_pbi
-- Project    : regtool
-------------------------------------------------------------------------------
-- File       : tb_regtool_pbi.vhd
-- Author     : Mathieu Rosiere
-- Company    : 
-- Created    : 2026-10-23
-- Platform   : 
-- Standard   : VHDL'08
-------------------------------------------------------------------------------
-- Description:
--  Testbench of the CSR tbcsr generated with the interface "pbi" :
--  tb_pbi_master -> tbcsr_registers (bridge pbi2mem), scenario TEST (tb_regtool_scenario)
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
use     asylum.pbi_pkg.all;
use     asylum.tbcsr_csr_pkg.all;
use     asylum.tb_regtool_pkg.all;

entity tb_regtool_pbi is
  generic (
    TEST       : string := "reset"
    );
end entity tb_regtool_pbi;

architecture tb of tb_regtool_pbi is

  signal clk        : std_logic;
  signal arst_b     : std_logic;
  signal req        : tb_req_t;
  signal rsp        : tb_rsp_t;
  signal sw2hw      : tbcsr_sw2hw_t;
  signal hw2sw      : tbcsr_hw2sw_t;

  signal pbi_ini    : pbi_ini_t(addr (TB_ADDR_WIDTH-1 downto 0),
                              wdata(TB_DATA_WIDTH-1 downto 0));
  signal pbi_tgt    : pbi_tgt_t(rdata(TB_DATA_WIDTH-1 downto 0));

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

  ins_master : entity work.tb_pbi_master
    port map
    (clk_i      => clk
    ,req_i      => req
    ,rsp_o      => rsp
    ,pbi_ini_o  => pbi_ini
    ,pbi_tgt_i  => pbi_tgt
    );

  ins_dut : tbcsr_registers
    port map
    (clk_i     => clk
    ,arst_b_i  => arst_b
    ,pbi_ini_i => pbi_ini
    ,pbi_tgt_o => pbi_tgt
    ,sw2hw_o   => sw2hw
    ,hw2sw_i   => hw2sw
    );

end architecture tb;
