-------------------------------------------------------------------------------
-- Title      : tb_axi4lite_master
-- Project    : regtool
-------------------------------------------------------------------------------
-- File       : tb_axi4lite_master.vhd
-- Author     : Mathieu Rosiere
-- Company    :
-- Created    : 2026-10-23
-- Platform   :
-- Standard   : VHDL'08
-------------------------------------------------------------------------------
-- Description:
--  AXI4-Lite manager :
--  - write : AW, then W one cycle later (the subordinate must wait for both)
--  - read  : AR
--  - bready / rready asserted RESP_DELAY cycles after bvalid / rvalid : the
--    response must be held (same rdata), the response must be OKAY
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
use     asylum.tb_regtool_pkg.all;

entity tb_axi4lite_master is
  generic (
    ADDR_WIDTH : natural := 8;
    RESP_DELAY : natural := 2
    );
  port (
    clk_i      : in  std_logic;
    req_i      : in  tb_req_t;
    rsp_o      : out tb_rsp_t;

    awvalid_o  : out std_logic;
    awready_i  : in  std_logic;
    awaddr_o   : out std_logic_vector(ADDR_WIDTH-1 downto 0);
    wvalid_o   : out std_logic;
    wready_i   : in  std_logic;
    wdata_o    : out std_logic_vector(TB_DATA_WIDTH-1 downto 0);
    wstrb_o    : out std_logic_vector(TB_DATA_WIDTH/8-1 downto 0);
    bvalid_i   : in  std_logic;
    bready_o   : out std_logic;
    bresp_i    : in  std_logic_vector(1 downto 0);
    arvalid_o  : out std_logic;
    arready_i  : in  std_logic;
    araddr_o   : out std_logic_vector(ADDR_WIDTH-1 downto 0);
    rvalid_i   : in  std_logic;
    rready_o   : out std_logic;
    rdata_i    : in  std_logic_vector(TB_DATA_WIDTH-1 downto 0);
    rresp_i    : in  std_logic_vector(1 downto 0)
    );
end entity tb_axi4lite_master;

architecture tb of tb_axi4lite_master is

begin  -- architecture tb

  process is
    variable done    : boolean := false;
    variable cycles  : natural;
    variable aw_done : boolean;
    variable w_done  : boolean;
    variable rdata   : std_logic_vector(TB_DATA_WIDTH-1 downto 0);

    -- Next rising edge
    procedure cycle is
    begin
      wait until rising_edge(clk_i);
      cycles := cycles + 1;
    end procedure cycle;

  begin  -- process
    awvalid_o <= '0';
    awaddr_o  <= (others => '0');
    wvalid_o  <= '0';
    wdata_o   <= (others => '0');
    wstrb_o   <= (others => '0');
    bready_o  <= '0';
    arvalid_o <= '0';
    araddr_o  <= (others => '0');
    rready_o  <= '0';
    rsp_o     <= TB_RSP_INIT;

    loop
      wait on req_i.start;
      wait until rising_edge(clk_i);
      cycles := 0;
      rdata  := (others => '0');

      if req_i.write then
        -- Write address, then write data one cycle later
        awvalid_o <= '1';
        awaddr_o  <= req_i.addr(ADDR_WIDTH-1 downto 0);
        cycle;
        tb_check(awready_i = '0', "AXI awready before wvalid");
        wvalid_o  <= '1';
        wdata_o   <= req_i.wdata;
        wstrb_o   <= (others => '1');

        aw_done   := false;
        w_done    := false;
        while not (aw_done and w_done) loop
          cycle;
          if awready_i = '1' then
            aw_done   := true;
            awvalid_o <= '0';
          end if;
          if wready_i = '1' then
            w_done    := true;
            wvalid_o  <= '0';
          end if;
        end loop;

        -- Write response
        loop
          cycle;
          exit when bvalid_i = '1';
        end loop;
        for i in 1 to RESP_DELAY loop
          cycle;
          tb_check(bvalid_i = '1', "AXI bvalid not held");
        end loop;
        bready_o  <= '1';
        cycle;
        tb_check(bvalid_i = '1'  , "AXI bvalid not held");
        tb_check(bresp_i  = "00" , "AXI bresp not OKAY");
        bready_o  <= '0';

      else
        -- Read address
        arvalid_o <= '1';
        araddr_o  <= req_i.addr(ADDR_WIDTH-1 downto 0);
        loop
          cycle;
          exit when arready_i = '1';
        end loop;
        arvalid_o <= '0';

        -- Read data
        loop
          cycle;
          exit when rvalid_i = '1';
        end loop;
        rdata     := rdata_i;
        for i in 1 to RESP_DELAY loop
          cycle;
          tb_check(rvalid_i = '1', "AXI rvalid not held");
        end loop;
        rready_o  <= '1';
        cycle;
        tb_check      (rvalid_i = '1' , "AXI rvalid not held");
        tb_check_equal(rdata_i, rdata , "AXI rdata not held");
        tb_check      (rresp_i  = "00", "AXI rresp not OKAY");
        rready_o  <= '0';
      end if;

      done   := not done;
      rsp_o  <= (done => done, rdata => rdata, cycles => cycles);
    end loop;
  end process;

end architecture tb;
