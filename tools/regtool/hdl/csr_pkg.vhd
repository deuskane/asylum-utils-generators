library IEEE;
use     IEEE.STD_LOGIC_1164.ALL;
use     IEEE.NUMERIC_STD.ALL;

package csr_pkg is
-- [COMPONENT_INSERT][BEGIN]
component csr_ext is
  
  generic (
    WIDTH : positive := 1                                 -- Register Width
    ); 

  port (
    -- Clock & Reset
    clk_i         : in  std_logic;                            -- Clock
    arst_b_i      : in  std_logic;                            -- Asynchronous Reset active low
    -- Software Side
    sw_wd_i       : in  std_logic_vector(WIDTH-1 downto 0);  -- Software Side Write Data
    sw_rd_o       : out std_logic_vector(WIDTH-1 downto 0);  -- Software Side Read  Data
    sw_we_i       : in  std_logic;                           -- Software Side Write Enable
    sw_re_i       : in  std_logic;                           -- Software Side Read  Enable
    sw_rbusy_o    : out std_logic;                           -- Software Side Read  Busy
    sw_wbusy_o    : out std_logic;                           -- Software Side Write Busy
    -- Hardware Side
    hw_wd_i       : in  std_logic_vector(WIDTH-1 downto 0);  -- Hardware Side Write Data
    hw_rd_o       : out std_logic_vector(WIDTH-1 downto 0);  -- Hardware Side Read  Data
    hw_we_i       : in  std_logic;                           -- Hardware Side Write Enable
    hw_sw_re_o    : out std_logic;                           -- Hardware Side CSR was Read
    hw_sw_we_o    : out std_logic                            -- Hardware Side CSR was Write
);
end component csr_ext;

component csr_fifo is
  
  generic (
    WIDTH          : positive := 1    ;
    BLOCKING_READ  : boolean  := false;
    BLOCKING_WRITE : boolean  := true ;
    DEPTH_SW2HW    : natural  := 0    ;
    DEPTH_HW2SW    : natural  := 0    
    ); 

  port (
    -- Clock & Reset
    clk_i                : in  std_logic;                           -- Clock
    arst_b_i             : in  std_logic;                           -- Asynchronous Reset active low

    -- Software Side
    sw_wd_i              : in  std_logic_vector(WIDTH-1 downto 0);  -- Software Side Write Data
    sw_rd_o              : out std_logic_vector(WIDTH-1 downto 0);  -- Software Side Read  Data
    sw_we_i              : in  std_logic;                           -- Software Side Write Enable
    sw_re_i              : in  std_logic;                           -- Software Side Read  Enable
    sw_rbusy_o           : out std_logic;                           -- Software Side Read  Busy
    sw_wbusy_o           : out std_logic;                           -- Software Side Write Busy

    -- Hardware Side
    hw_tx_valid_i        : in  std_logic;                           -- Hardware Side TX Valid
    hw_tx_ready_o        : out std_logic;                           -- Hardware Side TX Ready
    hw_tx_data_i         : in  std_logic_vector(WIDTH-1 downto 0);  -- Hardware Side TX Data
  --hw_tx_nb_elt_empty_o : out std_logic_vector;                    -- Number of free slot
  --hw_tx_nb_elt_full_o  : out std_logic_vector;                    -- Number of filled slot
    hw_tx_empty_o        : out std_logic;                           -- Hardware Side TX Empty Flag
    hw_tx_full_o         : out std_logic;                           -- Hardware Side TX Full  Flag
    
    hw_rx_valid_o        : out std_logic;                           -- Hardware Side RX Valid
    hw_rx_ready_i        : in  std_logic;                           -- Hardware Side RX Ready
    hw_rx_data_o         : out std_logic_vector(WIDTH-1 downto 0);  -- Hardware Side RX Data
  --hw_rx_nb_elt_empty_o : out std_logic_vector;                    -- Number of free slot
  --hw_rx_nb_elt_full_o  : out std_logic_vector;                    -- Number of filled slot
    hw_rx_empty_o        : out std_logic;                           -- Hardware Side RX Empty Flag
    hw_rx_full_o         : out std_logic                            -- Hardware Side RX Full  Flag
);
end component csr_fifo;

component csr_reg is
  
  generic (
    WIDTH : positive := 1;                              -- Register Width
    INIT  : std_logic_vector;                           -- Reset
    MODEL : string                                      -- "rw", "rw1c", "rw0c", "rw1s", "rw0s"
                              
    ); 

  port (
    -- Clock & Reset
    clk_i         : in  std_logic;                            -- Clock
    arst_b_i      : in  std_logic;                            -- Asynchronous Reset active low
    -- Software Side
    sw_wd_i       : in  std_logic_vector(WIDTH-1 downto 0);  -- Software Side Write Data
    sw_rd_o       : out std_logic_vector(WIDTH-1 downto 0);  -- Software Side Read  Data
    sw_we_i       : in  std_logic;                           -- Software Side Write Enable
    sw_re_i       : in  std_logic;                           -- Software Side Read  Enable
    sw_rbusy_o    : out std_logic;                           -- Software Side Read  Busy
    sw_wbusy_o    : out std_logic;                           -- Software Side Write Busy
    -- Hardware Side
    hw_wd_i       : in  std_logic_vector(WIDTH-1 downto 0);  -- Hardware Side Write Data
    hw_rd_o       : out std_logic_vector(WIDTH-1 downto 0);  -- Hardware Side Read  Data
    hw_we_i       : in  std_logic;                           -- Hardware Side Write Enable
    hw_sw_re_o    : out std_logic;                           -- Hardware Side CSR was Read
    hw_sw_we_o    : out std_logic                            -- Hardware Side CSR was Write
    );
end component csr_reg;

-- [COMPONENT_INSERT][END]

end csr_pkg;
