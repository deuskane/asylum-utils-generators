-------------------------------------------------------------------------------
-- Title      : axi4lite2mem
-- Project    : regtool
-------------------------------------------------------------------------------
-- File       : axi4lite2mem.vhd
-- Author     : Mathieu Rosiere
-- Company    :
-- Created    : 2026-10-23
-- Platform   :
-- Standard   : VHDL'93/02
-------------------------------------------------------------------------------
-- Description:
--  Bridge from an AXI4-Lite subordinate to the memory interface of the
--  regtool CSR (cs / re / we / addr / wdata / rdata / busy).
--  One access at a time :
--  - write : AW and W are accepted together (awready = wready), the memory
--            write is held until busy = '0', then the response is sent on B
--  - read  : AR is accepted, the memory read is held until busy = '0', the
--            read data is registered and sent on R
--  - read and write requested at the same time : round robin
--  Responses are always OKAY (an unmapped address reads 0).
--  wstrb is not used (full word writes).
-------------------------------------------------------------------------------
-- Copyright (c) 2026
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author   Description
-- 2026-10-23  1.0      mrosiere Created
-------------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;

entity axi4lite2mem is

  generic (
    ADDR_WIDTH : natural := 8;                               -- Address Width
    DATA_WIDTH : natural := 32                               -- Data Width
    );

  port (
    -- Clock & Reset
    clk_i           : in  std_logic;                         -- Clock
    arst_b_i        : in  std_logic;                         -- Asynchronous Reset active low
    -- AXI4-Lite Write Address Channel
    s_axi_awvalid_i : in  std_logic;
    s_axi_awready_o : out std_logic;
    s_axi_awaddr_i  : in  std_logic_vector(ADDR_WIDTH-1 downto 0);
    -- AXI4-Lite Write Data Channel
    s_axi_wvalid_i  : in  std_logic;
    s_axi_wready_o  : out std_logic;
    s_axi_wdata_i   : in  std_logic_vector(DATA_WIDTH-1 downto 0);
    s_axi_wstrb_i   : in  std_logic_vector(DATA_WIDTH/8-1 downto 0);
    -- AXI4-Lite Write Response Channel
    s_axi_bvalid_o  : out std_logic;
    s_axi_bready_i  : in  std_logic;
    s_axi_bresp_o   : out std_logic_vector(1 downto 0);
    -- AXI4-Lite Read Address Channel
    s_axi_arvalid_i : in  std_logic;
    s_axi_arready_o : out std_logic;
    s_axi_araddr_i  : in  std_logic_vector(ADDR_WIDTH-1 downto 0);
    -- AXI4-Lite Read Data Channel
    s_axi_rvalid_o  : out std_logic;
    s_axi_rready_i  : in  std_logic;
    s_axi_rdata_o   : out std_logic_vector(DATA_WIDTH-1 downto 0);
    s_axi_rresp_o   : out std_logic_vector(1 downto 0);
    -- Memory Interface
    cs_o            : out std_logic;                         -- Chip Select
    re_o            : out std_logic;                         -- Read  Enable
    we_o            : out std_logic;                         -- Write Enable
    addr_o          : out std_logic_vector(ADDR_WIDTH-1 downto 0); -- Address
    wdata_o         : out std_logic_vector(DATA_WIDTH-1 downto 0); -- Write Data
    rdata_i         : in  std_logic_vector(DATA_WIDTH-1 downto 0); -- Read  Data
    busy_i          : in  std_logic                          -- Access not completed
    );
end entity axi4lite2mem;

architecture rtl of axi4lite2mem is

  constant RESP_OKAY   : std_logic_vector(1 downto 0) := "00";

  type state_t is (S_IDLE, S_WRITE, S_BRESP, S_READ, S_RRESP);

  signal state_r       : state_t;
  signal addr_r        : std_logic_vector(ADDR_WIDTH-1 downto 0);
  signal wdata_r       : std_logic_vector(DATA_WIDTH-1 downto 0);
  signal rdata_r       : std_logic_vector(DATA_WIDTH-1 downto 0);
  signal read_prio_r   : std_logic;                          -- '1' : the read wins (last access was a write)

  signal write_req     : std_logic;
  signal read_req      : std_logic;
  signal write_start   : std_logic;
  signal read_start    : std_logic;

begin  -- architecture rtl

  -- Arbitration
  write_req       <= s_axi_awvalid_i and s_axi_wvalid_i;
  read_req        <= s_axi_arvalid_i;

  write_start     <= '1' when state_r = S_IDLE and write_req = '1' and (read_req  = '0' or read_prio_r = '0') else '0';
  read_start      <= '1' when state_r = S_IDLE and read_req  = '1' and (write_req = '0' or read_prio_r = '1') else '0';

  s_axi_awready_o <= write_start;
  s_axi_wready_o  <= write_start;
  s_axi_arready_o <= read_start;

  process (clk_i, arst_b_i) is
  begin  -- process
    if arst_b_i = '0' then              -- asynchronous reset (active low)
      state_r     <= S_IDLE;
      addr_r      <= (others => '0');
      wdata_r     <= (others => '0');
      rdata_r     <= (others => '0');
      read_prio_r <= '0';
    elsif rising_edge(clk_i) then
      case state_r is
        when S_IDLE =>
          if write_start = '1' then
            addr_r      <= s_axi_awaddr_i;
            wdata_r     <= s_axi_wdata_i;
            read_prio_r <= '1';
            state_r     <= S_WRITE;
          elsif read_start = '1' then
            addr_r      <= s_axi_araddr_i;
            read_prio_r <= '0';
            state_r     <= S_READ;
          end if;

        when S_WRITE =>
          if busy_i = '0' then
            state_r     <= S_BRESP;
          end if;

        when S_BRESP =>
          if s_axi_bready_i = '1' then
            state_r     <= S_IDLE;
          end if;

        when S_READ =>
          if busy_i = '0' then
            rdata_r     <= rdata_i;
            state_r     <= S_RRESP;
          end if;

        when S_RRESP =>
          if s_axi_rready_i = '1' then
            state_r     <= S_IDLE;
          end if;
      end case;
    end if;
  end process;

  -- Memory Interface
  cs_o            <= '1' when state_r = S_WRITE or state_r = S_READ else '0';
  we_o            <= '1' when state_r = S_WRITE else '0';
  re_o            <= '1' when state_r = S_READ  else '0';
  addr_o          <= addr_r;
  wdata_o         <= wdata_r;

  -- Responses
  s_axi_bvalid_o  <= '1' when state_r = S_BRESP else '0';
  s_axi_bresp_o   <= RESP_OKAY;
  s_axi_rvalid_o  <= '1' when state_r = S_RRESP else '0';
  s_axi_rdata_o   <= rdata_r;
  s_axi_rresp_o   <= RESP_OKAY;

end architecture rtl;
