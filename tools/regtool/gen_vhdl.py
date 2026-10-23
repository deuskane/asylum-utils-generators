"""
Module gen_vhdl.py
VHDL generator of regtool : CSR package and CSR module.
"""

from   csr_model import parse_value, parse_init_value

#--------------------------------------------
#--------------------------------------------
def print_vhdl_header_csr(csr,file):
    file.write( "--==================================\n")
    file.write(f"-- Module      : {csr['name']}\n")
    file.write(f"-- Description : {csr['desc']}\n")
    file.write(f"-- Width       : {csr['width']}\n")
    file.write( "--==================================\n")
        
#--------------------------------------------
#--------------------------------------------
def print_vhdl_header_reg(reg,file):
    file.write( "  --==================================\n")
    file.write(f"  -- Register    : {reg['name']}\n")
    file.write(f"  -- Description : {reg['desc']}\n")
    file.write(f"  -- Address     : 0x{reg['address']:X}\n")
    file.write(f"  -- Width       : {reg['width']}\n")
    file.write(f"  -- Sw Access   : {reg['swaccess']}\n")
    file.write(f"  -- Hw Access   : {reg['hwaccess']}\n")
    file.write(f"  -- Hw Type     : {reg['hwtype']}\n")
    file.write( "  --==================================\n")

#--------------------------------------------
#--------------------------------------------
def print_vhdl_header_field(field,file):
    file.write( "  --==================================\n")
    file.write(f"  -- Field       : {field['name']}\n")
    file.write(f"  -- Description : {field['desc']}\n")
    file.write(f"  -- Width       : {field['width']}\n")
    file.write( "  --==================================\n")

#--------------------------------------------
#--------------------------------------------
def generate_vhdl_package(csr, output_path):
    module = csr['name']
    
    with open(output_path, 'w') as file:
        file.write(f"-- Generated VHDL Package for {module}\n\n")
        file.write( "library IEEE;\n")
        file.write( "use     IEEE.STD_LOGIC_1164.ALL;\n")
        file.write( "use     IEEE.NUMERIC_STD.ALL;\n\n")
        if csr["interface"] == "pbi":
            file.write(f"library {csr['logical_name']};\n")
            file.write(f"use     {csr['logical_name']}.pbi_pkg.all;\n")
        if csr["interface"] == "sbi":
            file.write(f"library {csr['logical_name']};\n")
            file.write(f"use     {csr['logical_name']}.sbi_pkg.all;\n")
        
        print_vhdl_header_csr(csr,file)
        file.write( "\n")
        file.write(f"package {module}_csr_pkg is\n\n")

        file.write( "  ------------------------------------\n")
        file.write(f"  -- Global Constants\n")
        file.write( "  ------------------------------------\n")
        file.write( "\n")
        file.write(f"  constant {module.upper()}_ADDR_WIDTH : natural := {csr['size_addr']};\n")
        file.write(f"  constant {module.upper()}_DATA_WIDTH : natural := {csr['width']};\n")
        file.write( "\n")

        # Generate structs for each register
        for reg in csr['registers']:
            print_vhdl_header_reg(reg,file)
            
            file.write(f"  constant {module.upper()}_{reg['name'].upper()} : unsigned({module.upper()}_ADDR_WIDTH-1 downto 0) := to_unsigned({reg['address']}, {module.upper()}_ADDR_WIDTH);\n")
            file.write( "\n")
        
            if (reg['sw2hw']):
                file.write(f"  type {module}_{reg['name']}_sw2hw_t is record\n")

                if reg['sw2hw_re']:
                    file.write(f"    {reg['sw2hw_name_re']} : std_logic;\n")
                if reg['sw2hw_we']:
                    file.write(f"    {reg['sw2hw_name_we']} : std_logic;\n")
                if reg['sw2hw_data']:
                    for field in reg['fields']:
                        print_vhdl_header_field(field,file)
                        file.write(f"    {field['name']} : std_logic_vector({field['width']}-1 downto 0);\n")
                    if reg['hwtype'] in ['fifo']:
                        file.write(f"    sw2hw_empty : std_logic;\n")
                        file.write(f"    sw2hw_full  : std_logic;\n")
                if reg['hw2sw_data']:
                    if reg['hwtype'] in ['fifo']:
                        file.write(f"    hw2sw_empty : std_logic;\n")
                        file.write(f"    hw2sw_full  : std_logic;\n")
                file.write(f"  end record {module}_{reg['name']}_sw2hw_t;\n")
                file.write( "\n")

            if (reg['hw2sw']):
                file.write(f"  type {module}_{reg['name']}_hw2sw_t is record\n")
                if reg['hw2sw_re']:
                    file.write(f"    {reg['hw2sw_name_re']} : std_logic;\n")
                if reg['hw2sw_we']:
                    file.write(f"    {reg['hw2sw_name_we']} : std_logic;\n")
                if reg['hw2sw_data']:
                    for field in reg['fields']:
                        print_vhdl_header_field(field,file)
                        file.write(f"    {field['name']} : std_logic_vector({field['width']}-1 downto 0);\n")
                        
                file.write(f"  end record {module}_{reg['name']}_hw2sw_t;\n")
                file.write( "\n")
            for field in reg['fields']:
                for enum in field.get('enum', []):
                    file.write(f"-- Enum        : {reg['name']}.{field['name']}.{enum['name']}\n")
                    file.write(f"-- Description : {enum['desc']}\n")
                    file.write(f"constant {module.upper()}_{reg['name'].upper()}_{field['name'].upper()}_{enum['name'].upper()}     : std_logic_vector({field['width']}-1 downto 0) := \"{parse_init_value(parse_value(enum['value']),field['width'])}\";\n")
                    file.write(f"constant {module.upper()}_{reg['name'].upper()}_{field['name'].upper()}_{enum['name'].upper()}_RAW : std_logic_vector({csr['width']}-1 downto 0) := \"{parse_init_value(parse_value(enum['value'])<<field['lsb'],csr['width'])}\";\n")
                    file.write( "\n")


        # Generate global struct containing all registers
        file.write( "  ------------------------------------\n")
        file.write(f"  -- Structure {module}_t\n")
        file.write( "  ------------------------------------\n")
        
        sw2hw_regs = [reg for reg in csr['registers'] if reg['sw2hw']]
        if sw2hw_regs:
            file.write(f"  type {module}_sw2hw_t is record\n")
            for reg in sw2hw_regs:
                file.write(f"    {reg['name']} : {module}_{reg['name']}_sw2hw_t;\n")
            file.write(f"  end record {module}_sw2hw_t;\n")
            file.write( "\n")

        hw2sw_regs = [reg for reg in csr['registers'] if reg['hw2sw']]
        if hw2sw_regs:
            file.write(f"  type {module}_hw2sw_t is record\n")
            for reg in hw2sw_regs:
                file.write(f"    {reg['name']} : {module}_{reg['name']}_hw2sw_t;\n")
            file.write(f"  end record {module}_hw2sw_t;\n")
            file.write( "\n")
        
        file.write( "  ------------------------------------\n")
        file.write(f"  -- Component\n")
        file.write( "  ------------------------------------\n")
        generate_vhdl_entity(csr, file, "component")
        file.write( "\n")

        file.write(f"end package {module}_csr_pkg;\n")

        #file.write(f"package body {module}_csr_pkg is\n")
        #file.write(f"end package body {module}_csr_pkg;\n")

#--------------------------------------------
#--------------------------------------------
def generate_vhdl_entity(csr, file, entity_type):
    module = csr['name']

    # Generate VHDL entity and architecture
    file.write(f"{entity_type} {module}_registers is\n")
    file.write( "  generic (\n")
    file.write(f"    MODULE_NAME :  string := \"\" -- Name of the module\n")
    if csr['parameters'] != []:
        first = True
        for param in csr['parameters']:
            file.write(f"   ;{param['name']} : {param['type']} -- {param['desc']}\n")
              
    file.write( "  );\n")
    
    file.write( "  port (\n")
    file.write( "    -- Clock and Reset\n")
    file.write( "    clk_i      : in  std_logic\n")
    file.write( "   ;arst_b_i   : in  std_logic\n")
    file.write( "    -- Bus\n")

    # Generate Port for interface "reg"
    if csr["interface"] == "reg":
        
        file.write(f"   ;cs_i       : in    std_logic\n")
        file.write(f"   ;re_i       : in    std_logic\n")
        file.write(f"   ;we_i       : in    std_logic\n")
        file.write(f"   ;addr_i     : in    std_logic_vector ({csr['size_addr']}-1 downto 0)\n")
        file.write(f"   ;wdata_i    : in    std_logic_vector ({csr['width']}-1 downto 0)\n")
        file.write(f"   ;rdata_o    : out   std_logic_vector ({csr['width']}-1 downto 0)\n")
        file.write(f"   ;busy_o     : out   std_logic\n")

    # Generate Port for interface "pbi"
    if csr["interface"] == "pbi":
        
        file.write( "   ;pbi_ini_i  : in  pbi_ini_t\n")
        file.write( "   ;pbi_tgt_o  : out pbi_tgt_t\n")

    # Generate Port for interface "sbi"
    if csr["interface"] == "sbi":
        
        file.write( "   ;sbi_ini_i  : in  sbi_ini_t\n")
        file.write( "   ;sbi_tgt_o  : out sbi_tgt_t\n")

    file.write( "    -- CSR\n")
    sw2hw_regs = [reg for reg in csr['registers'] if reg['sw2hw']]
    if sw2hw_regs:
        file.write(f"   ;sw2hw_o    : out {module}_sw2hw_t\n")
    hw2sw_regs = [reg for reg in csr['registers'] if reg['hw2sw']]
    if hw2sw_regs:
        file.write(f"   ;hw2sw_i    : in  {module}_hw2sw_t\n")
    file.write( "  );\n")
    file.write(f"end {entity_type} {module}_registers;\n\n")
        
#--------------------------------------------
#--------------------------------------------
def generate_vhdl_module(csr, output_path):
    module = csr['name']
    
    with open(output_path, 'w') as file:
        file.write(f"-- Generated VHDL Module for {module}\n\n")
        file.write( "\n")
        file.write( "library IEEE;\n")
        file.write( "use     IEEE.STD_LOGIC_1164.ALL;\n")
        file.write( "use     IEEE.NUMERIC_STD.ALL;\n\n")
        file.write(f"library {csr['logical_name']};\n")
        file.write(f"use     {csr['logical_name']}.{module}_csr_pkg.ALL;\n")
        file.write(f"library {csr['logical_name']};\n")
        file.write(f"use     {csr['logical_name']}.csr_pkg.ALL;\n")
        if csr["interface"] == "pbi":
            file.write(f"library {csr['logical_name']};\n")
            file.write(f"use     {csr['logical_name']}.pbi_pkg.all;\n")
        if csr["interface"] == "sbi":
            file.write(f"library {csr['logical_name']};\n")
            file.write(f"use     {csr['logical_name']}.sbi_pkg.all;\n")
        file.write( "\n")

        print_vhdl_header_csr(csr,file)
        
        # Generate VHDL entity and architecture
        generate_vhdl_entity(csr, file, "entity")

        sig_wcs     = ""
        sig_we      = ""
        sig_waddr   = ""
        sig_wdata   = ""
                    
        sig_rcs     = ""
        sig_re      = ""
        sig_raddr   = ""
        sig_rdata   = ""
                    
        sig_busy    = ""
        sig_busy_op = ""
        
        # Generate Port for interface "reg"
        if csr["interface"] == "reg":
            sig_wcs   = "cs_i"
            sig_we    = "we_i"
            sig_waddr = "addr_i"
            sig_wdata = "wdata_i"

            sig_rcs   = "cs_i"
            sig_re    = "re_i"
            sig_raddr = "addr_i"
            sig_rdata = "rdata_o"

            sig_busy  = "busy_o"

        # Generate Port for interface "pbi"
        if csr["interface"] == "pbi":

            sig_wcs   = "pbi_ini_i.cs"
            sig_we    = "pbi_ini_i.we"
            sig_waddr = "pbi_ini_i.addr"
            sig_wdata = "pbi_ini_i.wdata"

            sig_rcs   = "pbi_ini_i.cs"
            sig_re    = "pbi_ini_i.re"
            sig_raddr = "pbi_ini_i.addr"
            sig_rdata = "pbi_tgt_o.rdata"

            sig_busy  = "pbi_tgt_o.busy"

        # Generate Port for interface "sbi"
        if csr["interface"] == "sbi":

            sig_wcs     = "sbi_ini_i.cs"
            sig_we      = "sbi_ini_i.we"
            sig_waddr   = "sbi_ini_i.addr"
            sig_wdata   = "sbi_ini_i.wdata"
                        
            sig_rcs     = "sbi_ini_i.cs"
            sig_re      = "sbi_ini_i.re"
            sig_raddr   = "sbi_ini_i.addr"
            sig_rdata   = "sbi_tgt_o.rdata"

            sig_busy    = "sbi_tgt_o.ready"
            sig_busy_op = "not "
        # Architecture
        file.write(f"architecture rtl of {module}_registers is\n")
        file.write( "\n")

        # Declare tmp signal (easier for debug)
        file.write( "  signal   sig_wcs   : std_logic;\n")
        file.write( "  signal   sig_we    : std_logic;\n")
        file.write(f"  signal   sig_waddr : unsigned({module}_ADDR_WIDTH-1 downto 0);\n")
        file.write(f"  signal   sig_wdata : std_logic_vector({sig_wdata}'length-1 downto 0);\n")
        file.write( "  signal   sig_wbusy : std_logic;\n")
        file.write( "\n")
        file.write( "  signal   sig_rcs   : std_logic;\n")
        file.write( "  signal   sig_re    : std_logic;\n")
        file.write(f"  signal   sig_raddr : unsigned({module}_ADDR_WIDTH-1 downto 0);\n")
        file.write(f"  signal   sig_rdata : std_logic_vector({sig_rdata}'length-1 downto 0);\n")
        file.write( "  signal   sig_rbusy : std_logic;\n")
        file.write( "\n")
        file.write( "  signal   sig_busy  : std_logic;\n")
        file.write( "\n")
        
        # Declare register and field signals
        for reg in csr['registers']:


            if reg['hwtype'] in ['reg']:
                file.write(f"  function INIT_{reg['name']}\n")
                file.write(f"    return std_logic_vector is\n")
                file.write(f"    variable tmp : std_logic_vector({reg['width']}-1 downto 0);\n")
                file.write(f"  begin  -- function INIT_{reg['name']}\n")
                lsb=0
                for field in reg['fields']:
                    msb=lsb+field['width']-1
                    file.write(f"    tmp({msb} downto {lsb}) := {field['expr']}; -- {field['name']}\n")
                    lsb=msb+1
                file.write(f"    return tmp;\n")
                file.write(f"  end function INIT_{reg['name']};\n")
                file.write( "\n")

            file.write(f"  signal   {reg['name']}_wcs       : std_logic;\n");
            file.write(f"  signal   {reg['name']}_we        : std_logic;\n");
            file.write(f"  signal   {reg['name']}_wdata     : std_logic_vector({csr['width']}-1 downto 0);\n");
            file.write(f"  signal   {reg['name']}_wdata_sw  : std_logic_vector({reg['width']}-1 downto 0);\n");
            if reg['hw2sw_data']:
                file.write(f"  signal   {reg['name']}_wdata_hw  : std_logic_vector({reg['width']}-1 downto 0);\n");
            file.write(f"  signal   {reg['name']}_wbusy     : std_logic;\n");
            #for field in reg['fields']:
            #    file.write(f"  signal   {reg['name']}_{field['name']}_wdata : std_logic_vector({field['msb']} downto {field['lsb']});\n");
            file.write( "\n")
                                                            
            file.write(f"  signal   {reg['name']}_rcs       : std_logic;\n");
            file.write(f"  signal   {reg['name']}_re        : std_logic;\n");
            file.write(f"  signal   {reg['name']}_rdata     : std_logic_vector({csr['width']}-1 downto 0);\n");
            file.write(f"  signal   {reg['name']}_rdata_sw  : std_logic_vector({reg['width']}-1 downto 0);\n");
            file.write(f"  signal   {reg['name']}_rdata_hw  : std_logic_vector({reg['width']}-1 downto 0);\n");
            file.write(f"  signal   {reg['name']}_rbusy     : std_logic;\n");
            #for field in reg['fields']:
            #    file.write(f"  signal   {reg['name']}_{field['name']}_rdata : std_logic_vector({field['msb']} downto {field['lsb']});\n");
            file.write( "\n")

        file.write( "begin  -- architecture rtl\n")
        file.write( "\n")

        file.write( "  -- Interface \n")
        file.write(f"  sig_wcs   <= {sig_wcs};\n")
        file.write(f"  sig_we    <= {sig_we};\n")
        file.write(f"  sig_waddr <= unsigned({sig_waddr}({module}_ADDR_WIDTH-1 downto 0));\n")
        file.write(f"  sig_wdata <= {sig_wdata};\n")
        file.write( "\n")
        file.write(f"  sig_rcs   <= {sig_rcs};\n")
        file.write(f"  sig_re    <= {sig_re};\n")
        file.write(f"  sig_raddr <= unsigned({sig_raddr}({module}_ADDR_WIDTH-1 downto 0));\n")
        file.write(f"  {sig_rdata} <= sig_rdata;\n")
        file.write(f"  {sig_busy} <= {sig_busy_op}sig_busy;\n")
        file.write( "\n")
        file.write(f"  sig_busy  <= sig_wbusy when sig_we = '1' else\n")
        file.write(f"               sig_rbusy when sig_re = '1' else\n")
        file.write(f"               '0';\n")
        file.write( "\n")

        
        for reg in csr['registers']:

            file.write(f"  gen_{reg['name']}: if ({reg['enable']})\n")
            file.write(f"  generate\n")
            
            print_vhdl_header_reg(reg,file)

            for field in reg['fields']:
                print_vhdl_header_field(field,file)
                file.write( "\n")
                

            file.write( "\n")
            if reg['sw2hw_re']:
                file.write(f"    {reg['name']}_rcs     <= '1' when (sig_raddr = {module}_{reg['name'].upper()}) else '0';\n")
                file.write(f"    {reg['name']}_re      <= sig_rcs and sig_re and {reg['name']}_rcs;\n")

                #lsb=0
                #for field in reg['fields']:
                #    msb=lsb+field['width']-1
                #    file.write(f"    {reg['name']}_{field['name']}_rdata({field['msb']} downto {field['lsb']}) <= {reg['name']}_rdata_sw({msb} downto {lsb});\n")
                #    lsb=msb+1

                file.write(f"    {reg['name']}_rdata   <= (\n");
                x=0
                assigned_width = 0
                for field in reg['fields']:
                    assigned_width += field['width']
                    y=0
                    for i in range(field['lsb'], field['msb']+1):
                        prefix = " " if x == 0 else ","
                        file.write(f"      {prefix}{i} => {reg['name']}_rdata_sw({x}) -- {field['name']}({y})\n")
                        x=x+1
                        y=y+1
                if assigned_width < csr['width']:
                    file.write(f"      ,others => '0'\n")
                file.write(f"      );\n")

            else:
                file.write(f"    {reg['name']}_rcs     <= '0';\n")
                file.write(f"    {reg['name']}_re      <= '0';\n")
                file.write(f"    {reg['name']}_rdata   <= (others=>'0');\n");

            file.write( "\n")

            if reg['sw2hw_we']:
                file.write(f"    {reg['name']}_wcs     <= '1' when ")
                prefix="    "
                for waddr in reg['address_write']:
                    file.write(f"  {prefix}(sig_waddr = {module}_{waddr.upper()})")
                    prefix=" or"
                
                file.write(f"   else '0';\n")
                file.write(f"    {reg['name']}_we      <= sig_wcs and sig_we and {reg['name']}_wcs;\n")
                file.write(f"    {reg['name']}_wdata   <= sig_wdata;\n")
                #lsb=0
                #for field in reg['fields']:
                #    msb=lsb+field['width']-1
                #    file.write(f"    {reg['name']}_{field['name']}_wdata({field['msb']} downto {field['lsb']}) <= {reg['name']}_wdata({field['msb']} downto {field['lsb']});\n")
                #    lsb=msb+1
                lsb=0
                for field in reg['fields']:
                    msb=lsb+field['width']-1
                    file.write(f"    {reg['name']}_wdata_sw({msb} downto {lsb}) <= {reg['name']}_wdata({field['msb']} downto {field['lsb']}); -- {field['name']}\n")
                    lsb=msb+1

            else:
                # No software write : <reg>_wbusy is driven by the instance
                file.write(f"    {reg['name']}_wcs      <= '0';\n") 
                file.write(f"    {reg['name']}_we       <= '0';\n")
                file.write(f"    {reg['name']}_wdata    <= (others=>'0');\n")
                file.write(f"    {reg['name']}_wdata_sw <= (others=>'0');\n")
                
            if reg['hw2sw_data']:
                lsb=0
                for field in reg['fields']:
                    msb=lsb+field['width']-1
                    file.write(f"    {reg['name']}_wdata_hw({msb} downto {lsb}) <= hw2sw_i.{reg['name']}.{field['name']}; -- {field['name']}\n")
                    lsb=msb+1

            if reg['sw2hw_data']:
                lsb=0
                for field in reg['fields']:
                    msb=lsb+field['width']-1
                    file.write(f"    sw2hw_o.{reg['name']}.{field['name']} <= {reg['name']}_rdata_hw({msb} downto {lsb}); -- {field['name']}\n")
                    lsb=msb+1

            file.write( "\n")

            file.write(f"    ins_{reg['name']} : csr_{reg['hwtype']}\n")
            file.write( "      generic map\n")
            file.write(f"        (WIDTH         => {reg['width']}\n")
            
            if reg['hwtype'] in ['reg']:
                file.write(f"        ,INIT          => INIT_{reg['name']}\n")
                file.write(f"        ,MODEL         => \"{reg['swaccess']}\"\n")
            if reg['hwtype'] in ['fifo']:
                if 'params' in reg:
                    params=reg['params']
                    for param in reg['params']:
                        file.write(f"        ,{param} => {params[param]}\n")
                
            file.write( "        )\n")
            file.write( "      port map\n")
            file.write( "        (clk_i         => clk_i\n")
            file.write( "        ,arst_b_i      => arst_b_i\n")
            file.write(f"        ,sw_wd_i       => {reg['name']}_wdata_sw\n")
            file.write(f"        ,sw_rd_o       => {reg['name']}_rdata_sw\n")
            file.write(f"        ,sw_we_i       => {reg['name']}_we\n")
            file.write(f"        ,sw_re_i       => {reg['name']}_re\n")
            file.write(f"        ,sw_rbusy_o    => {reg['name']}_rbusy\n")
            file.write(f"        ,sw_wbusy_o    => {reg['name']}_wbusy\n")

            if reg['hwtype'] in ['reg','ext']:
                if reg['hw2sw_data']:
                    file.write(f"        ,hw_wd_i       => {reg['name']}_wdata_hw\n")
                else:
                    file.write(f"        ,hw_wd_i       => (others => '0')\n")
                if reg['sw2hw_data']:
                    file.write(f"        ,hw_rd_o       => {reg['name']}_rdata_hw\n")
                else:
                    file.write(f"        ,hw_rd_o       => open\n")
                if reg['hw2sw_we']:
                    file.write(f"        ,hw_we_i       => hw2sw_i.{reg['name']}.{reg['hw2sw_name_we']}\n")
                else:
                    file.write(f"        ,hw_we_i       => '0'\n")
                if reg['sw2hw_re']:
                    file.write(f"        ,hw_sw_re_o    => sw2hw_o.{reg['name']}.{reg['sw2hw_name_re']}\n")
                else:
                    file.write(f"        ,hw_sw_re_o    => open\n")
                if reg['sw2hw_we']:
                    file.write(f"        ,hw_sw_we_o    => sw2hw_o.{reg['name']}.{reg['sw2hw_name_we']}\n")
                else:
                    file.write(f"        ,hw_sw_we_o      => open\n")

            if reg['hwtype'] in ['fifo']:
                if reg['hw2sw_we']:
                    file.write(f"        ,hw_tx_valid_i        => hw2sw_i.{reg['name']}.{reg['hw2sw_name_we']}\n")
                else:
                    file.write(f"        ,hw_tx_valid_i        => '0'\n")
                if reg['sw2hw_re']:
                    file.write(f"        ,hw_tx_ready_o        => sw2hw_o.{reg['name']}.{reg['sw2hw_name_re']}\n")
                else:
                    file.write(f"        ,hw_tx_ready_o        => open\n")
                if reg['hw2sw_data']:
                    file.write(f"        ,hw_tx_data_i         => {reg['name']}_wdata_hw\n")
                    file.write(f"        ,hw_tx_empty_o        => sw2hw_o.{reg['name']}.hw2sw_empty\n")
                    file.write(f"        ,hw_tx_full_o         => sw2hw_o.{reg['name']}.hw2sw_full\n") 
                   #file.write(f"        ,hw_tx_nb_elt_empty_o => open\n")
                   #file.write(f"        ,hw_tx_nb_elt_full_o  => open\n")
                else:
                    file.write(f"        ,hw_tx_data_i         => (others => '0')\n")
                    file.write(f"        ,hw_tx_empty_o        => open\n")
                    file.write(f"        ,hw_tx_full_o         => open\n")
                   #file.write(f"        ,hw_tx_nb_elt_empty_o => open\n")
                   #file.write(f"        ,hw_tx_nb_elt_full_o  => open\n")

                if reg['sw2hw_we']:
                    file.write(f"        ,hw_rx_valid_o        => sw2hw_o.{reg['name']}.{reg['sw2hw_name_we']}\n")
                else:
                    file.write(f"        ,hw_rx_valid_o        => open\n")
                if reg['hw2sw_re']:
                    file.write(f"        ,hw_rx_ready_i        => hw2sw_i.{reg['name']}.{reg['hw2sw_name_re']}\n")
                else:
                    file.write(f"        ,hw_rx_ready_i        => '1'\n")
                if reg['sw2hw_data']:
                    file.write(f"        ,hw_rx_data_o         => {reg['name']}_rdata_hw\n")
                    file.write(f"        ,hw_rx_empty_o        => sw2hw_o.{reg['name']}.sw2hw_empty\n")
                    file.write(f"        ,hw_rx_full_o         => sw2hw_o.{reg['name']}.sw2hw_full\n")
                   #file.write(f"        ,hw_rx_nb_elt_empty_o => open\n")
                   #file.write(f"        ,hw_rx_nb_elt_full_o  => open\n")
                else:
                    file.write(f"        ,hw_rx_data_o         => open\n")
                    file.write(f"        ,hw_rx_empty_o        => open\n")
                    file.write(f"        ,hw_rx_full_o         => open\n")
                   #file.write(f"        ,hw_rx_nb_elt_empty_o => open\n")
                   #file.write(f"        ,hw_rx_nb_elt_full_o  => open\n")

                    
            file.write( "        );\n")
            file.write( "\n")
            file.write(f"  end generate gen_{reg['name']};\n")
            file.write( "\n")
            file.write(f"  gen_{reg['name']}_b: if not ({reg['enable']})\n")
            file.write(f"  generate\n")
            file.write(f"    {reg['name']}_rcs     <= '0';\n")
            file.write(f"    {reg['name']}_rbusy   <= '0';\n")
            file.write(f"    {reg['name']}_rdata   <= (others => '0');\n");
            file.write(f"    {reg['name']}_wcs      <= '0';\n") 
            file.write(f"    {reg['name']}_wbusy    <= '0';\n")
            if reg['sw2hw_data']:
                for field in reg['fields']:
                    file.write(f"    sw2hw_o.{reg['name']}.{field['name']} <= {field['expr']};\n")
                if reg['hwtype'] in ['fifo']:
                    file.write(f"    sw2hw_o.{reg['name']}.sw2hw_empty <= '1';\n")
                    file.write(f"    sw2hw_o.{reg['name']}.sw2hw_full  <= '0';\n")
            if reg['hw2sw_data']:
                if reg['hwtype'] in ['fifo']:
                    file.write(f"    sw2hw_o.{reg['name']}.hw2sw_empty <= '1';\n")
                    file.write(f"    sw2hw_o.{reg['name']}.hw2sw_full  <= '0';\n")
            if reg['sw2hw_re']:
                file.write(f"    sw2hw_o.{reg['name']}.{reg['sw2hw_name_re']} <= '0';\n")
            if reg['sw2hw_we']:
                file.write(f"    sw2hw_o.{reg['name']}.{reg['sw2hw_name_we']} <= '0';\n")
            file.write(f"  end generate gen_{reg['name']}_b;\n")
            file.write( "\n")

        file.write(f"  sig_wbusy <= \n");
        for reg in csr['registers']:
            file.write(f"    {reg['name']}_wbusy when {reg['name']}_wcs = '1' else\n");
        file.write(f"    '0'; -- Bad Address, no busy\n")

        file.write(f"  sig_rbusy <= \n");
        for reg in csr['registers']:
            file.write(f"    {reg['name']}_rbusy when {reg['name']}_rcs = '1' else\n");
        file.write(f"    '0'; -- Bad Address, no busy\n")

        file.write(f"  sig_rdata <= \n");
        for reg in csr['registers']:
            file.write(f"    {reg['name']}_rdata when {reg['name']}_rcs = '1' else\n");
        file.write(f"    (others => '0'); -- Bad Address, return 0\n")

#        file.write( "\n")
#        file.write( "-- pragma translate_off\n")
#        file.write( "\n")
#        file.write( "  process is\n")
#        file.write( "  begin  -- process\n")
#        file.write( "\n")
#        file.write(f"    report \"Address Size : \"&integer'image(sig_raddr'length) severity note;\n");  
#        file.write(f"    report \"Data    Size : \"&integer'image(sig_raddr'length) severity note;\n");  
#
#        file.write( "\n")
#        file.write( "    wait;\n")
#        file.write( "  end process;\n")
#        file.write( "\n")
#        file.write( "-- pragma translate_on  \n")
#        file.write( "\n")


        if csr["interface"] == "sbi":
            file.write( "\n")

            file.write(f"  gen_tgt_info_name : if MODULE_NAME = \"\"\n")
            file.write( "  generate\n")
            file.write(f"    sbi_tgt_o.info.name <= to_sbi_name(\"{csr['name']}\");\n")
            file.write(f"  else generate\n")
            file.write(f"    sbi_tgt_o.info.name <= to_sbi_name(MODULE_NAME);\n")
            file.write(f"  end generate;\n")

        file.write( "end architecture rtl;\n")
