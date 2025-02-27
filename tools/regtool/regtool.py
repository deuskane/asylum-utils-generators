"""
Module regtool.py
Ce module contient des outils pour manipuler les registres.
"""

import argparse
import hjson
import math
from   prettytable import PrettyTable

#--------------------------------------------
#--------------------------------------------
class AddrMap:
    """
    A class to manage register addresses ensuring unique register names and addresses.

    Attributes
    ----------
    registers : dict
        A dictionary to store register names and their corresponding addresses.

    Methods
    -------
    add(name, address):
        Adds a new register with a unique name and address.
    
    get(name):
        Retrieves the address of a given register name.
    
    rm(name):
        Removes a register by its name.
    
    display():
        Displays a table of all registers with their names and addresses.
    """

    def __init__(self):
        """
        Initializes the AddrMap class with an empty dictionary to store registers.
        """
        self.registers = {}

    def add(self, name, address):
        """
        Adds a new register with a unique name and address.

        Parameters
        ----------
        name : str
            The name of the register.
        address : str
            The address of the register.

        Raises
        ------
        ValueError
            If the register name or address already exists.
        """
        if name    in self.registers:
            raise ValueError(f"Name '{name}' already exists.")
        if address in self.registers.values():
            raise ValueError(f"Address '{address}' already exists.")
        self.registers[name] = address

    def get(self, name):
        """
        Retrieves the address of a given register name.

        Parameters
        ----------
        name : str
            The name of the register.

        Returns
        -------
        str or None
            The address of the register if found, otherwise None.
        """
        return self.registers.get(name, None)

    def rm(self, name):
        """
        Removes a register by its name.

        Parameters
        ----------
        name : str
            The name of the register to be removed.

        Raises
        ------
        ValueError
            If the register name does not exist.
        """
        if name in self.registers:
            del self.registers[name]
        else:
            raise ValueError(f"Name '{name}' does not exist.")

    def display(self):
        """
        Displays a table of all registers with their names and addresses.
        
        Returns
        -------
        None
            Prints a table of all registers with their names and addresses.
        """
        
        table = PrettyTable()
        
        table.field_names = ["Name", "Address"]
        
        for name, address in self.registers.items():
            table.add_row([address, name])
        
        print(table)

#--------------------------------------------
#--------------------------------------------
def check_key(d, key, mandatory=True, default_value=None ):
    """
    Checks if the key is present in the dictionary. If the mandatory parameter is True,
    raises an error if the key is not present. Otherwise, adds the key to the dictionary
    with the given default value.

    :param d: The dictionary to check.
    :param key: The key to check.
    :param mandatory: Boolean indicating if the key is mandatory.
    :param default_value: The default value to add if the key is not present.
    :return: The updated dictionary.
    """

    if key not in d:
        if mandatory:
            raise KeyError(f"The key '{key}' is mandatory but not present in the dictionary.")
        else:
            d[key] = default_value
    return d

#--------------------------------------------
#--------------------------------------------
def check_reg_width(csr):
    """
    Checks if a number is a power of 2 and at least 8.
    Returns the number of byte of the number if true, otherwise raises an exception.

    :param n: The number to check.
    :return: The log2 of the number if it is a power of 2 and at least 8.
    :raises ValueError: If the number is not a power of 2 or is less than 8.
    """
    n = csr['width']
    if n >= 8 and (n & (n - 1)) == 0:
        csr['addr_offset'] = int(n/8)
    else:
        raise ValueError(f"The number {n} is not a power of 2 or is less than 8.")

#--------------------------------------------
#--------------------------------------------
def check_reg_addr(reg,addrmap,addr_offset):
    """
    Checks if the address is already present in the addrmap dictionary.
    If the address is present, raises an error. Otherwise, adds the address to the addrmap.

    :param reg: Dictionary of register.
    :param addrmap: Discotionary of Address.
    :param addr_offset: mandatory offset between 2 registers 
    :raises ValueError: If the address is already present in the addrmap.
    """
    reg['address'] = parse_value(reg['address'])

    if reg['address'] & (addr_offset-1) != 0 :
        raise ValueError(f"The address {reg['address']} have invalid offset {addr_offset}.")

    addrmap.add(reg['name'],reg['address'])

#--------------------------------------------
#--------------------------------------------
def check_swaccess(reg):
    """
    Checks access is valid value

    :param reg: Dictionary of register.
    :raises ValueError: If swaccess is not valid
    """
    access  = ['rw','wo','ro','rw1c', 'rw0c', 'rw1s', 'rw0s']

    list_re = ['rw', 'ro','rw1c', 'rw0c', 'rw1s', 'rw0s']
    list_we = ['rw', 'wo','rw1c', 'rw0c', 'rw1s', 'rw0s']
    
    if reg['swaccess'] not in access:
        raise KeyError(f"swaccess '{reg['swaccess']}' must be in {access}.")

    reg['sw_reg_re'] = reg['swaccess'] in list_re
    reg['sw_reg_we'] = reg['swaccess'] in list_we

#--------------------------------------------
#--------------------------------------------
def check_hwaccess(reg):
    """
    Checks access is valid value

    :param reg: Dictionary of register.
    :raises ValueError: If hwaccess is not valid
    """
    access  = ['rw','wo','ro',"none"]

    list_re = ['rw', 'ro']
    list_we = ['rw', 'wo']
    
    if reg['hwaccess'] not in access:
        raise KeyError(f"hwaccess '{reg['hwaccess']}' must be in {access}.")

    reg['hw_reg_re'] = reg['hwaccess'] in list_re
    reg['hw_reg_we'] = reg['hwaccess'] in list_we

#--------------------------------------------
#--------------------------------------------
def check_alias(csr,reg):
    """
    Checks if alias is valide

    :param reg: Dictionary of register.
    :raises ValueError: If alias is not valid
    """

    check_key(reg,'address_write',False,[])


    if reg['alias_write'] == None :
        reg['address_write'].append(reg['address'])
    
    if reg['alias_write'] != None :
        if reg['alias_write'] == reg['name']:
            raise KeyError(f"Register '{reg['name']}', self aliases (alias_write {reg['alias_write']}).")

        reg_alias = next((item for item in csr['registers'] if item.get('name') == reg['alias_write']), None)
        
        if reg_alias == None:
            raise KeyError(f"Register '{reg['name']}', alias_write {reg['alias_write']} is not valid register.")

        check_key(reg_alias,'address_write',False,[])

        reg_alias['address_write'].append(reg['address'])
    
#--------------------------------------------
#--------------------------------------------
def check_range(csr,field,regmap):
    """
    Check range value and add un addrmap

    :param csr: Dictionary of csr
    :param field: Dictionary of field
    :param regmap: Register Map
    :raises ValueError: bits is invalid
    """
    
    msb,lsb    = parse_bits(field['bits'])

    if msb < lsb:
        raise KeyError(f"field {field['name']} : msb ({msb}) is lower than lsb ({lsb})")

    width      = msb-lsb+1

    if msb >= csr['width'] :
        raise KeyError(f"field {field['name']} : msb ({msb}) is greater or equal than csr width ({csr['width']})")

    if lsb < 0 :
        raise KeyError(f"field {field['name']} : lsb ({lsb}) is lower than 0")
    
    for i in range(msb, lsb-1, -1):
        regmap.add(field['name']+'['+str(i)+']',i)
    
    field['msb']   = msb
    field['lsb']   = lsb
    field['width'] = width
    
#--------------------------------------------
#--------------------------------------------
def parse_hjson(file_path):
    """
    Read the file
    
    :param file_path: Path to the hjson file
    :return: Return an hjson structure
    """
    with open(file_path, 'r') as file:
        csr=hjson.load(file)

    addr_max=0
    addr    = 0
    addrmap = AddrMap()

    # Check Global variables
    check_key      (csr,'name')
    check_key      (csr,'desc',      False)
    check_key      (csr,'width',     False,32)
    check_reg_width(csr)

    for reg in csr['registers']:
        # Check Register variables
        check_key      (reg,'name')
        check_key      (reg,'desc',       False)
        check_key      (reg,'address',    False,str(addr))
        check_reg_addr (reg,addrmap,csr['addr_offset'])        
        addr += reg['address']+csr['addr_offset'];
        if addr_max < reg['address']:
            addr_max = reg['address']
        check_key      (reg,'hwaccess',   False,"rw")
        check_key      (reg,'swaccess',   False,"rw")
        check_swaccess (reg)
        check_hwaccess (reg)
        check_key      (reg,'hwext',      False,False)
        check_key      (reg,'alias_write',False,None)
        check_alias    (csr,reg)
        
        regmap = AddrMap()
        for field in reg['fields']:
            # Check Field variables
            check_key      (field,'name')
            check_key      (field,'desc',      False)
            check_key      (field,'init',      False,"0")
            field['init'] = parse_value(field['init'])
            check_key      (field,'bits')
            
            check_range    (csr,field,regmap)

    csr['size_addr'] = int(math.ceil(math.log2(addr_max)))
    addrmap.display()

    return csr

#--------------------------------------------
#--------------------------------------------
def parse_value(value):
    """
    Read the value and transform in binary
    
    :param value: Init value from hjson
    :param width: Width of the value
    :return: Return an hjson structure
    """
    if   value.startswith('b'):
        return int(value[1:], 2)
    elif value.startswith('o'):
        return int(value[1:], 8)
    elif value.startswith('x'):
        return int(value[1:], 16)
    elif value.startswith('d'):
        return int(value[1:])
    else:
        # default : decimal
        return int(value)

#--------------------------------------------
#--------------------------------------------
def parse_init_value(init_value, width):
    """
    Read the value and transform in binary
    
    :param init_value: Init value from hjson
    :param width: Width of the value
    :return: Return an hjson structure
    """

    return f"{init_value:0{width}b}"

#--------------------------------------------
#--------------------------------------------
def parse_bits(bits):
    """
    Cette fonction extrait le MSB (Most Significant Bit) et le LSB (Least Significant Bit)
    à partir d'un champ bits qui peut prendre un numéro de bit ou un champ de bit de type 5:3.

    :param bits: Champ bits sous forme de chaîne de caractères.
    :return: Tuple contenant le MSB et le LSB.
    """
    if ':' in bits:
        msb, lsb = map(int, bits.split(':'))
    else:
        msb = lsb = int(bits)
    
    return msb, lsb    

#--------------------------------------------
#--------------------------------------------
def generate_c_header(csr, output_path):
    module = csr['name']
    
    with open(output_path, 'w') as file:
        file.write(f"#ifndef {module.upper()}_REGISTERS_H\n")
        file.write(f"#define {module.upper()}_REGISTERS_H\n")
        file.write( "\n")
        file.write( "#include <stdint.h>\n")
        file.write( "\n")

        file.write(f"// Module      : {csr['name']}\n")
        file.write(f"// Description : {csr['desc']}\n")
        file.write(f"// Width       : {csr['width']}\n")
        file.write( "\n")
        
        regmap = {}
        
        # Define structs for each register
        for reg in csr['registers']:
            regmap[reg['address']] = reg['name'];
            
            file.write( "//==================================\n")
            file.write(f"// Register    : {reg['name']}\n")
            file.write(f"// Description : {reg['desc']}\n")
            file.write(f"// Address     : 0x{reg['address']:X}\n")
            file.write( "//==================================\n")

            file.write(f"#define {module.upper()}_{reg['name'].upper()} 0x{reg['address']:X}\n")
            file.write( "\n")

            for field in reg['fields']:
                file.write(f"// Field       : {reg['name']}.{field['name']}\n")
                file.write(f"// Description : {field['desc']}\n")
                if (field['width'] == 1):
                    file.write(f"// Range       : [{field['lsb']}]\n")
                else:
                    file.write(f"// Range       : [{field['msb']}:{field['lsb']}]\n")
                file.write(f"#define {module.upper()}_{reg['name'].upper()}_{field['name'].upper()}      {field['lsb']}\n")
                file.write(f"#define {module.upper()}_{reg['name'].upper()}_{field['name'].upper()}_MASK {(1<<field['width'])-1}\n")

                file.write( "\n")
                
            
        file.write( "//----------------------------------\n")
        file.write( "// Structure {module}_t\n")
        file.write( "//----------------------------------\n")

        # Last address covered
        curaddr = 0;
        
        # Define global struct containing all registers
        file.write(f"typedef struct {{\n")

        for addr in sorted(regmap.keys()):
            for i in range(curaddr, addr, csr['addr_offset']):
                file.write(f"  uint{csr['width']}_t __dummy_0x{i:X}__\n")
            curaddr = addr+csr['addr_offset']
            file.write(f"  uint{csr['width']}_t {regmap[addr]}; // 0x{addr:X}\n")
        file.write(f"}} {module}_t;\n")

        file.write(f"\n#endif // {module.upper()}_REGISTERS_H\n")

#--------------------------------------------
#--------------------------------------------
def generate_vhdl_package(csr, output_path):
    module = csr['name']
    
    with open(output_path, 'w') as file:
        file.write(f"-- Generated VHDL Package for {module}\n\n")
        file.write( "library IEEE;\n")
        file.write( "use     IEEE.STD_LOGIC_1164.ALL;\n")
        file.write( "use     IEEE.NUMERIC_STD.ALL;\n\n")
        
        file.write(f"-- Module      : {csr['name']}\n")
        file.write(f"-- Description : {csr['desc']}\n")
        file.write(f"-- Width       : {csr['width']}\n")
        file.write( "\n")
        file.write(f"package {module}_csr_pkg is\n\n")

        # Generate structs for each register
        for reg in csr['registers']:
            file.write( "  --==================================\n")
            file.write(f"  -- Register    : {reg['name']}\n")
            file.write(f"  -- Description : {reg['desc']}\n")
            file.write(f"  -- Address     : 0x{reg['address']:X}\n")
            file.write( "  --==================================\n")
            file.write(f"  type {module}_{reg['name']}_t is record\n")

            file.write(f"    re : std_logic;\n")
            file.write(f"    we : std_logic;\n")
            for field in reg['fields']:
                file.write(f"    -- Field       : {reg['name']}.{field['name']}\n")
                file.write(f"    -- Description : {field['desc']}\n")
                file.write(f"    {field['name']} : std_logic_vector({field['width']}-1 downto 0);\n")
            file.write(f"  end record {module}_{reg['name']}_t;\n\n")
        
        # Generate global struct containing all registers
        file.write( "  ------------------------------------\n")
        file.write( "  -- Structure {module}_t\n")
        file.write( "  ------------------------------------\n")
        file.write(f"  type {module}_t is record\n")
        for reg in csr['registers']:
            file.write(f"    {reg['name']} : {module}_{reg['name']}_t;\n")
        file.write(f"  end record {module}_t;\n\n")

        file.write(f"end package {module}_csr_pkg;\n\n")

        #file.write(f"package body {module}_csr_pkg is\n\n")
        #file.write(f"end package body {module}_csr_pkg;\n")

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
        file.write(f"library {csr['logical_name']};\n");
        file.write(f"use     {csr['logical_name']}.{module}_csr_pkg.ALL;\n");
        file.write( "\n")

        # Generate VHDL entity and architecture
        file.write(f"entity {module}_registers is\n")
        file.write( "  port (\n")
        file.write( "    -- Clock and Reset\n")
        file.write( "    clk_i      : in  std_logic;\n")
        file.write( "    arst_b_i   : in  std_logic;\n")
        file.write( "    -- Bus\n")
        file.write(f"    cs_i       : in    std_logic;\n")
        file.write(f"    re_i       : in    std_logic;\n")
        file.write(f"    we_i       : in    std_logic;\n")
        file.write(f"    addr_i     : in    std_logic_vector ({csr['size_addr']}-1 downto 0);\n")
        file.write(f"    wdata_i    : in    std_logic_vector ({csr['width']}-1 downto 0);\n")
        file.write(f"    rdata_o    : out   std_logic_vector ({csr['width']}-1 downto 0);\n")
        file.write(f"    busy_o     : out   std_logic;\n")
        #file.write( "    pbi_ini_i  : in  pbi_ini_t;\n")
        #file.write( "    pbi_tgt_o  : out pbi_tgt_t;\n")
        file.write( "    -- CSR\n")
        file.write(f"    sw2hw_o    : out {module}_t;\n")
        file.write(f"    hw2sw_i    : in  {module}_t\n")
        file.write( "  );\n")
        file.write(f"end entity {module}_registers;\n\n")

        file.write(f"architecture rtl of {module}_registers is\n")
        file.write( "\n")
        #file.write( "  constant SIZE_ADDR : integer := pbi_ini_i.addr'length;")
        file.write(f"  constant SIZE_ADDR : integer := {csr['size_addr']};")
        file.write( "\n")

        for reg in csr['registers']:
            for field in reg['fields']:
                file.write(f"  signal   {reg['name']}_wcs   : std_logic;\n");
                file.write(f"  signal   {reg['name']}_rcs   : std_logic;\n");
                file.write(f"  signal   {reg['name']}_we    : std_logic;\n");
                file.write(f"  signal   {reg['name']}_re    : std_logic;\n");
                file.write(f"  signal   {reg['name']}_rdata : std_logic_vector({csr['width']}-1 downto 0);\n");
                file.write(f"  signal   {reg['name']}_wdata : std_logic_vector({csr['width']}-1 downto 0);\n");
                file.write(f"  signal   {reg['name']}_{field['name']}_rdata : std_logic_vector({field['msb']} downto {field['lsb']});\n");
                file.write( "\n")

        file.write( "begin  -- architecture rtl\n")
        file.write( "\n")
        for reg in csr['registers']:
            file.write( "  --==================================\n")
            file.write(f"  -- Register    : {reg['name']}\n")
            file.write(f"  -- Description : {reg['desc']}\n")
            file.write(f"  -- Address     : 0x{reg['address']:X}\n")
            file.write(f"  -- Hw External : {reg['hwext']}\n")
            file.write( "  --==================================\n")
            file.write( "\n")
            file.write(f"  {reg['name']}_rcs     <= '1' when     (addr_i = std_logic_vector(to_unsigned({reg['address']},SIZE_ADDR))) else '0';\n")

            if reg['address_write'] == []:
                file.write(f"  {reg['name']}_wcs     <= '0';\n")
            else:
                file.write(f"  {reg['name']}_wcs     <= '1' when ")
                prefix="    "
                for waddr in reg['address_write']:
                    file.write(f"{prefix}(addr_i = std_logic_vector(to_unsigned({waddr},SIZE_ADDR)))")
                    prefix=" or "
                
                file.write(f" else '0';\n")

            file.write(f"  {reg['name']}_we     <= cs_i and {reg['name']}_wcs and we_i;\n")
            file.write(f"  {reg['name']}_re     <= cs_i and {reg['name']}_rcs and re_i;\n")
            file.write(f"  {reg['name']}_wdata  <= wdata_i;\n")
            file.write(f"  {reg['name']}_rdata  <= (\n");
            for field in reg['fields']:
                for i in range(field['msb'], field['lsb']-1, -1):
                    file.write(f"    {i} => {reg['name']}_{field['name']}_rdata({i}),\n")
            file.write(f"    others => '0') when {reg['name']}_rcs = '1' else (others => '0');\n")
            file.write( "\n")

            for field in reg['fields']:
                file.write(f"  -- Field       : {reg['name']}.{field['name']}\n")
                file.write(f"  -- Description : {field['desc']}\n")

                if reg['hwext']:
                    file.write(f"  {reg['name']}_{field['name']}_rdata <= hw2sw_i.{reg['name']}.{field['name']};\n")
                    file.write(f"  sw2hw_o.{reg['name']}.{field['name']} <= {reg['name']}_wdata({field['msb']} downto {field['lsb']});\n")
                    file.write(f"  sw2hw_o.{reg['name']}.re <= {reg['name']}_re;\n")
                    file.write(f"  sw2hw_o.{reg['name']}.we <= {reg['name']}_we;\n")

                else:
                    file.write(f"  ins_{reg['name']}_{field['name']} : entity work.csr_reg(rtl)\n")
                    file.write( "    generic map\n")
                    file.write(f"      (WIDTH       => {field['width']}\n")
                    file.write(f"      ,INIT        => \"{parse_init_value(field['init'],field['width'])}\"\n")
                    file.write(f"      ,MODEL       => \"{reg['swaccess']}\"\n")
                    file.write( "      )\n")
                    file.write( "    port map\n")
                    file.write( "      (clk_i       => clk_i\n")
                    file.write( "      ,arst_b_i    => arst_b_i\n")
                    file.write(f"      ,sw_wd_i     => {reg['name']}_wdata({field['msb']} downto {field['lsb']})\n")
                    file.write(f"      ,sw_rd_o     => {reg['name']}_{field['name']}_rdata\n")
                    file.write(f"      ,sw_we_i     => {reg['name']}_we\n")
                    file.write(f"      ,sw_re_i     => {reg['name']}_re\n")
                    file.write(f"      ,hw_wd_i     => hw2sw_i.{reg['name']}.{field['name']}\n")
                    file.write(f"      ,hw_rd_o     => sw2hw_o.{reg['name']}.{field['name']}\n")
                    file.write(f"      ,hw_we_i     => hw2sw_i.{reg['name']}.we\n")
                    file.write(f"      ,hw_sw_re_o  => sw2hw_o.{reg['name']}.re\n")
                    file.write(f"      ,hw_sw_we_o  => sw2hw_o.{reg['name']}.we\n")
                    file.write( "      );\n")
                file.write( "\n")

        #file.write(f"  pbi_tgt_o.busy  <= '0';\n");
        #file.write(f"  pbi_tgt_o.rdata <= \n");
        file.write(f"  busy_o  <= '0';\n");
        file.write(f"  rdata_o <= \n");
        first = True
        for reg in csr['registers']:
            if not first :
                file.write( " or\n")
            file.write(f"    {reg['name']}_rdata");
            
            first = False;
        file.write( ";\n")
        file.write( "end architecture rtl;\n")

#--------------------------------------------
#--------------------------------------------
def main():
    parser = argparse.ArgumentParser(description='Generate VHDL and C files from HJSON input.')
    parser.add_argument('input_file'    , type=str,  help='Path to the HJSON input file')
    parser.add_argument('--vhdl_package', type=str,  help='Path to the VHDL package output file')
    parser.add_argument('--vhdl_module' , type=str,  help='Path to the VHDL module output file')
    parser.add_argument('--c_header'    , type=str,  help='Path to the C header output file')
    parser.add_argument('--logical_name', type=str,  help='Library', default='work')
    
    args         = parser.parse_args()

    csr          = parse_hjson(args.input_file)
    csr['logical_name'] = args.logical_name
    
    
    # Define output file names if not provided
    vhdl_package = args.vhdl_package or f"{csr['name']}_csr_pkg.vhd"
    vhdl_module  = args.vhdl_module  or f"{csr['name']}_csr.vhd"
    c_header     = args.c_header     or f"{csr['name']}_csr.h"
    
    generate_vhdl_package (csr, vhdl_package)
    generate_vhdl_module  (csr, vhdl_module)
    generate_c_header     (csr, c_header)
    print(f"VHDL package generated in {vhdl_package}")
    print(f"VHDL module  generated in {vhdl_module}")
    print(f"C    header  generated in {c_header}")

if __name__ == "__main__":
    main()
