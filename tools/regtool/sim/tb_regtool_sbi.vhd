-------------------------------------------------------------------------------
-- Title      : tb_regtool_sbi
-- Project    : regtool
-------------------------------------------------------------------------------
-- File       : tb_regtool_sbi.vhd
-- Author     : Mathieu Rosiere
-- Company    : 
-- Created    : 2026-10-23
-- Platform   : 
-- Standard   : VHDL'08
-------------------------------------------------------------------------------
-- Description:
--  Testbench of the CSR tbcsr generated with the interface "sbi" :
--  tb_sbi_master -> tbcsr_registers (bridge sbi2mem), scenario TEST (tb_regtool_scenario)
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
use     asylum.sbi_pkg.all;
use     asylum.tbcsr_csr_pkg.all;
use     asylum.tb_regtool_pkg.all;

entity tb_regtool_sbi is
  generic (
    TEST       : string := "reset"
    );
end entity tb_regtool_sbi;

architecture tb of tb_regtool_sbi is

  signal clk        : std_logic;
  signal arst_b     : std_logic;
  signal req        : tb_req_t;
  signal rsp        : tb_rsp_t;
  signal sw2hw      : tbcsr_sw2hw_t;
  signal hw2sw      : tbcsr_hw2sw_t;

  signal sbi_ini    : sbi_ini_t(addr (TB_ADDR_WIDTH-1 downto 0),
                              wdata(TB_DATA_WIDTH-1 downto 0));
  signal sbi_tgt    : sbi_tgt_t(rdata(TB_DATA_WIDTH-1 downto 0));

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

  ins_master : entity work.tb_sbi_master
    port map
    (clk_i      => clk
    ,req_i      => req
    ,rsp_o      => rsp
    ,sbi_ini_o  => sbi_ini
    ,sbi_tgt_i  => sbi_tgt
    );

  ins_dut : tbcsr_registers
    port map
    (clk_i     => clk
    ,arst_b_i  => arst_b
    ,sbi_ini_i => sbi_ini
    ,sbi_tgt_o => sbi_tgt
    ,sw2hw_o   => sw2hw
    ,hw2sw_i   => hw2sw
    );

end architecture tb;
