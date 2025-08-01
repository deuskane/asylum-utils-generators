"""
Module regtool.py
Ce module contient des outils pour manipuler les registres.
"""

import argparse
import hjson
import jsonschema
from   jsonschema import validate
import math
from   addrmap import AddrMap
import os

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
    :raises KeyError: Rise error if mandatory is true and key in not in dictionary

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

    :param csr: Dictionary of csr
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
def check_interface(csr):
    """
    Checks interface is valid value

    :param csr: Dictionary of csr.
    :raises ValueError: If interface is not valid
    """
    interface           = ['reg','pbi']

    if csr['interface'] not in interface:
        raise KeyError(f"interface '{csr['interface']}' must be in {interface}.")
    
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
def check_access(reg):
    """
    Checks access is valid value

    :param reg: Dictionary of register.
    :raises ValueError: If swaccess is not valid or if hwaccess is not valid
    """
    swaccess           = ['rw','wo','ro','rw1c', 'rw0c', 'rw1s', 'rw0s']

    if reg['swaccess'] not in swaccess:
        raise KeyError(f"swaccess '{reg['swaccess']}' must be in {swaccess}.")

    hwaccess           = ['rw','wo','ro',"none"]
    
    if reg['hwaccess'] not in hwaccess:
        raise KeyError(f"hwaccess '{reg['hwaccess']}' must be in {hwaccess}.")

    hwtype             = ['reg','ext','fifo']

    if reg['hwtype'] not in hwtype:
        raise KeyError(f"hwtype '{reg['hwtype']}' must be in {hwtype}.")
    
    list_sw_re         = ['rw', 'ro','rw1c', 'rw0c', 'rw1s', 'rw0s']
    list_sw_we         = ['rw', 'wo','rw1c', 'rw0c', 'rw1s', 'rw0s']
    
    list_hw_re         = ['rw', 'ro']
    list_hw_we         = ['rw', 'wo']
    
    reg['sw2hw_re']    = reg['swaccess'] in list_sw_re
    reg['sw2hw_we']    = reg['swaccess'] in list_sw_we
    reg['hw2sw_re']    = reg['hwaccess'] in list_hw_re and reg['hwtype'] == 'fifo'
    reg['hw2sw_we']    = reg['hwaccess'] in list_hw_we
    reg['hw2sw_data']  = reg['hwaccess'] in list_hw_we
    reg['sw2hw_data']  = reg['hwaccess'] in list_hw_re
    
    reg['sw2hw']       = reg['sw2hw_re'] or reg['sw2hw_we'] or reg['sw2hw_data']
    reg['hw2sw']       = reg['hw2sw_re'] or reg['hw2sw_we'] or reg['hw2sw_data']

    if reg['alias_write'] != None :
        reg['sw2hw_we'] = False

    if reg['hwtype'] in ['fifo']:
        reg['sw2hw_name_re']    = "ready"
        reg['sw2hw_name_we']    = "valid"
        reg['hw2sw_name_re']    = "ready"
        reg['hw2sw_name_we']    = "valid"

    else:
        reg['sw2hw_name_re']    = "re"
        reg['sw2hw_name_we']    = "we"
        reg['hw2sw_name_re']    = "re"
        reg['hw2sw_name_we']    = "we"

#--------------------------------------------
#--------------------------------------------
def check_enable(params,reg):
    """
    Checks Enable Register

    :param params: Dictionary of parameters
    :param reg: Dictionary of register.
    :raises ValueError: If enable is not boolean or not an parameter or not a parameter not boolean
    """

    enable            = reg['enable']
    boolean           = ['True','False']

    if enable in boolean:
        return

    find = False
    for param in params:
        if param['name'] == enable:
            find = True
            if param['type'] != "boolean":
                raise KeyError(f"Register {reg['name']}.enable depend of {param['name']}, but type is {param['type']} insteand boolean.")

    if find == False:
        raise KeyError(f"Register {reg['name']}.enable = {enable} is not boolean and not parameter.")
        
#--------------------------------------------
#--------------------------------------------
def check_alias(csr,reg):
    """
    Checks if alias is valide

    :param reg: Dictionary of register.
    :raises ValueError: If alias is not valid
    """

    check_key(reg,'address_write',False,[])
    check_key(reg,'alias_write'  ,False,None)

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
def fill_defaults_recursive(schema, hjson):
    """
    Remplir les valeurs par défaut si elles sont absentes
    """
    if schema.get("type") == "object":
        for key, value in schema.get("properties", {}).items():
            if "default" in value and key not in hjson:
                hjson[key] = value["default"]
            if key in hjson:
                fill_defaults_recursive(value, hjson[key])
    elif schema.get("type") == "array":
        for item in hjson:
            fill_defaults_recursive(schema.get("items"), item)
    return hjson

#--------------------------------------------
#--------------------------------------------
def parse_hjson(file_path):
    """
    Read the file
    
    :param file_path: Path to the hjson file
    :return: Return an hjson structure
    """

    # Open hjson file
    with open(file_path, 'r') as data_file:
        csr=hjson.load(data_file)

    # Open hjson schema
    with open(os.path.join(os.path.dirname(os.path.abspath(__file__)),'regtool_schema.hjson'), 'r') as schema_file:
        schema = hjson.load(schema_file)

    # Data validate
    try:
        validate(instance=csr, schema=schema)
        print(f"The hjson file {file_path} is valide.")
    except jsonschema.exceptions.ValidationError as err:
        print(f"The hjson file {file_path} is invalide.")
        print(f"  {err.message}")
        raise err

   # Dumper le HJSON dans un fichier
    with open(csr['name']+'_dump1.hjson', 'w') as f:
        hjson.dump(csr, f, ensure_ascii=False)
    
    csr     = fill_defaults_recursive(schema, csr)

    with open(csr['name']+'_dump2.hjson', 'w') as f:
        hjson.dump(csr, f, ensure_ascii=False)

    addr_max= 0
    addr    = 0
    addrmap = AddrMap()

    # Check Global variables
    check_reg_width(csr)
    check_interface(csr)
    check_key      (csr,'parameters',False,[])
    
    for reg in csr['registers']:
        # Check Register variables
        check_key      (reg,'address',    False,str(addr))
        check_reg_addr (reg,addrmap,csr['addr_offset'])        
        addr = reg['address']+csr['addr_offset'];
        if addr_max < reg['address']:
            addr_max = reg['address']
        check_alias    (csr,reg)
        check_access   (reg)
        check_enable   (csr['parameters'],reg)

        regmap = AddrMap()
        reg['width'] = 0;
        for field in reg['fields']:
            # Check Field variables
            field['init'] = parse_value(field['init'])
            
            check_range    (csr,field,regmap)
            reg['width'] += field['width'];
            if field['expr'] == '':
                field['expr'] = f"\"{parse_init_value(field['init'],field['width'])}\""
        
    csr['size_addr'] = int(math.ceil(math.log2(addr_max+1)))
    addrmap.display()

    with open(csr['name']+'_dump3.hjson', 'w') as f:
        hjson.dump(csr, f, ensure_ascii=False)

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
def generate_doc_markdown(csr, output_path):
    module = csr['name']

    regmap = {}
        
    # Define structs for each register
    for reg in csr['registers']:
        regmap[reg['address']] = reg['name'];

    
    with open(output_path, 'w') as file:
        file.write(f"# {csr['name']}\n")
        file.write(f"{csr['desc']}\n")
        file.write( "\n")
        file.write( "| Address | Registers |\n")
        file.write( "|---------|-----------|\n")
        for addr in sorted(regmap.keys()):
            file.write(f"|0x{addr:X}|{regmap[addr]}|\n")
        file.write( "\n")
        
        # Define structs for each register
        for reg in csr['registers']:
            
            file.write(f"## 0x{reg['address']:X} {reg['name']}\n")
            file.write(f"{reg['desc']}\n")
            file.write( "\n")

            for field in reg['fields']:
                file.write(f"### [{field['msb']}:{field['lsb']}] {field['name']}\n")
                file.write(f"{field['desc']}\n")
                file.write( "\n")
        
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
        
        print_vhdl_header_csr(csr,file)
        file.write( "\n")
        file.write(f"package {module}_csr_pkg is\n\n")

        # Generate structs for each register
        for reg in csr['registers']:
            print_vhdl_header_reg(reg,file)

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

            
        # Generate global struct containing all registers
        file.write( "  ------------------------------------\n")
        file.write(f"  -- Structure {module}_t\n")
        file.write( "  ------------------------------------\n")
        file.write(f"  type {module}_sw2hw_t is record\n")
        for reg in csr['registers']:
            if (reg['sw2hw']):
                file.write(f"    {reg['name']} : {module}_{reg['name']}_sw2hw_t;\n")
        file.write(f"  end record {module}_sw2hw_t;\n")
        file.write( "\n")
        file.write(f"  type {module}_hw2sw_t is record\n")
        for reg in csr['registers']:
            if (reg['hw2sw']):
                file.write(f"    {reg['name']} : {module}_{reg['name']}_hw2sw_t;\n")
        file.write(f"  end record {module}_hw2sw_t;\n")
        file.write( "\n")
        file.write(f"  constant {module}_ADDR_WIDTH : natural := {csr['size_addr']};\n")
        file.write(f"  constant {module}_DATA_WIDTH : natural := {csr['width']};\n")
        file.write( "\n")
        
        file.write(f"end package {module}_csr_pkg;\n")

        #file.write(f"package body {module}_csr_pkg is\n")
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
        file.write(f"library {csr['logical_name']};\n")
        file.write(f"use     {csr['logical_name']}.{module}_csr_pkg.ALL;\n")
        if csr["interface"] == "pbi":
            file.write(f"library work;\n")
            file.write(f"use     work.pbi_pkg.all;\n")
        file.write( "\n")

        print_vhdl_header_csr(csr,file)
        
        # Generate VHDL entity and architecture
        file.write(f"entity {module}_registers is\n")
        if csr['parameters'] != []:
            file.write( "  generic (\n")
            first = True
            for param in csr['parameters']:
                if first == True:
                    file.write( "    ")
                else:
                    file.write( "   ;")
                file.write(f"{param['name']} : {param['type']} -- {param['desc']}\n")
                first = False;
                  
            file.write( "  );\n")

        
        file.write( "  port (\n")
        file.write( "    -- Clock and Reset\n")
        file.write( "    clk_i      : in  std_logic;\n")
        file.write( "    arst_b_i   : in  std_logic;\n")
        file.write( "    -- Bus\n")

        sig_wcs   = ""
        sig_we    = ""
        sig_waddr = ""
        sig_wdata = ""
        
        sig_rcs   = ""
        sig_re    = ""
        sig_raddr = ""
        sig_rdata = ""

        sig_busy  = ""

        # Generate Port for interface "reg"
        if csr["interface"] == "reg":
            
            file.write(f"    cs_i       : in    std_logic;\n")
            file.write(f"    re_i       : in    std_logic;\n")
            file.write(f"    we_i       : in    std_logic;\n")
            file.write(f"    addr_i     : in    std_logic_vector ({csr['size_addr']}-1 downto 0);\n")
            file.write(f"    wdata_i    : in    std_logic_vector ({csr['width']}-1 downto 0);\n")
            file.write(f"    rdata_o    : out   std_logic_vector ({csr['width']}-1 downto 0);\n")
            file.write(f"    busy_o     : out   std_logic;\n")

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
            
            file.write( "    pbi_ini_i  : in  pbi_ini_t;\n")
            file.write( "    pbi_tgt_o  : out pbi_tgt_t;\n")

            sig_wcs   = "pbi_ini_i.cs"
            sig_we    = "pbi_ini_i.we"
            sig_waddr = "pbi_ini_i.addr"
            sig_wdata = "pbi_ini_i.wdata"

            sig_rcs   = "pbi_ini_i.cs"
            sig_re    = "pbi_ini_i.re"
            sig_raddr = "pbi_ini_i.addr"
            sig_rdata = "pbi_tgt_o.rdata"

            sig_busy  = "pbi_tgt_o.busy"

        file.write( "    -- CSR\n")
        file.write(f"    sw2hw_o    : out {module}_sw2hw_t;\n")
        file.write(f"    hw2sw_i    : in  {module}_hw2sw_t\n")
        file.write( "  );\n")
        file.write(f"end entity {module}_registers;\n\n")

        # Architecture
        file.write(f"architecture rtl of {module}_registers is\n")
        file.write( "\n")

        # Declare tmp signal (easier for debug)
        file.write( "  signal   sig_wcs   : std_logic;\n")
        file.write( "  signal   sig_we    : std_logic;\n")
        file.write(f"  signal   sig_waddr : std_logic_vector({sig_waddr}'length-1 downto 0);\n")
        file.write(f"  signal   sig_wdata : std_logic_vector({sig_wdata}'length-1 downto 0);\n")
        file.write( "  signal   sig_wbusy : std_logic;\n")
        file.write( "\n")
        file.write( "  signal   sig_rcs   : std_logic;\n")
        file.write( "  signal   sig_re    : std_logic;\n")
        file.write(f"  signal   sig_raddr : std_logic_vector({sig_raddr}'length-1 downto 0);\n")
        file.write(f"  signal   sig_rdata : std_logic_vector({sig_rdata}'length-1 downto 0);\n")
        file.write( "  signal   sig_rbusy : std_logic;\n")
        file.write( "\n")
        file.write( "  signal   sig_busy  : std_logic;\n")
        file.write( "\n")
        
        # Declare register and field signals
        for reg in csr['registers']:
            file.write(f"  constant INIT_{reg['name']} : std_logic_vector({reg['width']}-1 downto 0) :=\n")
            first = True
            for field in reg['fields']:
                if not first :
                    file.write( "           & ")
                else:
                    file.write( "             ")

                file.write(f"{field['expr']} -- {field['name']}\n")
                first = False;
            file.write( "           ;\n")

            file.write(f"  signal   {reg['name']}_wcs       : std_logic;\n");
            file.write(f"  signal   {reg['name']}_we        : std_logic;\n");
            file.write(f"  signal   {reg['name']}_wdata     : std_logic_vector({csr['width']}-1 downto 0);\n");
            file.write(f"  signal   {reg['name']}_wdata_sw  : std_logic_vector({reg['width']}-1 downto 0);\n");
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
        file.write(f"  sig_waddr <= {sig_waddr};\n")
        file.write(f"  sig_wdata <= {sig_wdata};\n")
        file.write( "\n")
        file.write(f"  sig_rcs   <= {sig_rcs};\n")
        file.write(f"  sig_re    <= {sig_re};\n")
        file.write(f"  sig_raddr <= {sig_raddr};\n")
        file.write(f"  {sig_rdata} <= sig_rdata;\n")
        file.write(f"  {sig_busy} <= sig_busy;\n")
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
                file.write(f"    {reg['name']}_rcs     <= '1' when     (sig_raddr({module}_ADDR_WIDTH-1 downto 0) = std_logic_vector(to_unsigned({reg['address']},{module}_ADDR_WIDTH))) else '0';\n")
                file.write(f"    {reg['name']}_re      <= sig_rcs and sig_re and {reg['name']}_rcs;\n")

                #lsb=0
                #for field in reg['fields']:
                #    msb=lsb+field['width']-1
                #    file.write(f"    {reg['name']}_{field['name']}_rdata({field['msb']} downto {field['lsb']}) <= {reg['name']}_rdata_sw({msb} downto {lsb});\n")
                #    lsb=msb+1

                file.write(f"    {reg['name']}_rdata   <= (\n");
                x=0
                for field in reg['fields']:
                    y=0
                    for i in range(field['lsb'], field['msb']+1):
                        file.write(f"      {i} => {reg['name']}_rdata_sw({x}), -- {field['name']}({y})\n")
                        x=x+1
                        y=y+1
                file.write(f"      others => '0');\n")

            else:
                file.write(f"    {reg['name']}_rcs     <= '0';\n")
                file.write(f"    {reg['name']}_re      <= '0';\n")
                file.write(f"    {reg['name']}_rdata   <= (others=>'0');\n");

            file.write( "\n")

            if reg['sw2hw_we']:
                file.write(f"    {reg['name']}_wcs     <= '1' when ")
                prefix="    "
                for waddr in reg['address_write']:
                    file.write(f"  {prefix}(sig_waddr({module}_ADDR_WIDTH-1 downto 0) = std_logic_vector(to_unsigned({waddr},{module}_ADDR_WIDTH)))")
                    prefix=" or "
                
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
                file.write(f"    {reg['name']}_wcs      <= '0';\n") 
                file.write(f"    {reg['name']}_we       <= '0';\n")
                file.write(f"    {reg['name']}_wbusy    <= '0';\n")
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

            file.write(f"    ins_{reg['name']} : entity work.csr_{reg['hwtype']}(rtl)\n")
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
        
        file.write( "end architecture rtl;\n")

#--------------------------------------------
#--------------------------------------------
def main():
    parser = argparse.ArgumentParser(description='Generate VHDL and C files from HJSON input.')
    parser.add_argument('input_file'    , type=str,  help='Path to the HJSON input file')
    parser.add_argument('--vhdl_package', type=str,  help='Path to the VHDL package output file')
    parser.add_argument('--vhdl_module' , type=str,  help='Path to the VHDL module output file')
    parser.add_argument('--c_header'    , type=str,  help='Path to the C header output file')
    parser.add_argument('--doc_markdown', type=str,  help='Path to the Markdown Documentation output file')
    parser.add_argument('--logical_name', type=str,  help='Library', default='work')
    
    args         = parser.parse_args()

    csr          = parse_hjson(args.input_file)
    csr['logical_name'] = args.logical_name
    
    
    # Define output file names if not provided
    vhdl_package = args.vhdl_package or f"{csr['name']}_csr_pkg.vhd"
    vhdl_module  = args.vhdl_module  or f"{csr['name']}_csr.vhd"
    c_header     = args.c_header     or f"{csr['name']}_csr.h"
    doc_markdown = args.doc_markdown or f"{csr['name']}_csr.md"
    
    generate_vhdl_package (csr, vhdl_package)
    generate_vhdl_module  (csr, vhdl_module)
    generate_c_header     (csr, c_header)
    generate_doc_markdown (csr, doc_markdown)
    print(f"VHDL package  generated in {vhdl_package}")
    print(f"VHDL module   generated in {vhdl_module}")
    print(f"C    header   generated in {c_header}")
    print(f"Doc  markdown generated in {doc_markdown}")

if __name__ == "__main__":
    main()
