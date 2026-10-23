"""
Module csr_model.py
CSR model of regtool : reads the hjson description, validates it against
regtool_schema.hjson, checks it and computes the derived fields used by the
generators (gen_vhdl, gen_c, gen_markdown).
"""

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
    Checks interface is valid value.
    The CSR logic has only the memory interface ("mem"), the other
    interfaces are buses connected through a bridge <bus>2mem.
    "reg" is the former name of "mem".

    :param csr: Dictionary of csr.
    :raises ValueError: If interface is not valid
    """
    interface           = ['mem','reg','pbi','sbi','apb','axi4lite']

    if csr['interface'] not in interface:
        raise KeyError(f"interface '{csr['interface']}' must be in {interface}.")

    if csr['interface'] == 'reg':
        csr['interface'] = 'mem'
    
#--------------------------------------------
#--------------------------------------------
def check_reg_addr(reg,addrmap,addr_offset):
    """
    Checks the alignment of the address and adds the register to the addrmap.
    An address can be shared by several registers, see check_shared_address.

    :param reg: Dictionary of register.
    :param addrmap: Discotionary of Address.
    :param addr_offset: mandatory offset between 2 registers 
    :raises ValueError: If the address is not aligned.
    """
    reg['address'] = parse_value(reg['address'])

    if reg['address'] & (addr_offset-1) != 0 :
        raise ValueError(f"The address {reg['address']} have invalid offset {addr_offset}.")

    addrmap.add(reg['name'],reg['address'],unique_address=False)

#--------------------------------------------
#--------------------------------------------
def check_shared_address(csr):
    """
    Checks the registers sharing an address : at each address, the software
    reads at most one register and writes at most one register (own address
    or alias_write). Example : a write only command register and a read only
    status register at the same address.

    :param csr: Dictionary of csr.
    :raises ValueError: If an address is read or written by several registers.
    """
    address = {reg['name'] : reg['address'] for reg in csr['registers']}
    readers = {}
    writers = {}

    for reg in csr['registers']:
        if reg['sw2hw_re']:
            readers.setdefault(reg['address'],[]).append(reg['name'])
        if reg['sw2hw_we']:
            for waddr in reg['address_write']:
                writers.setdefault(address[waddr],[]).append(reg['name'])

    for addr,names in readers.items():
        if len(names) > 1:
            raise ValueError(f"Address 0x{addr:X} is read by several registers {names}.")

    for addr,names in writers.items():
        if len(names) > 1:
            raise ValueError(f"Address 0x{addr:X} is written by several registers {names}.")

    
#--------------------------------------------
#--------------------------------------------
def check_access(reg):
    """
    Checks access is valid value

    :param reg: Dictionary of register.
    :raises ValueError: If swaccess is not valid or if hwaccess is not valid
    """
    swaccess           = ['rw','wo','ro','rw1c', 'rw0c', 'rw1s', 'rw0s', 'rsw1c', 'rcw1s', 'rsw0c']

    if reg['swaccess'] not in swaccess:
        raise KeyError(f"swaccess '{reg['swaccess']}' must be in {swaccess}.")

    hwaccess           = ['rw','wo','ro',"none"]
    
    if reg['hwaccess'] not in hwaccess:
        raise KeyError(f"hwaccess '{reg['hwaccess']}' must be in {hwaccess}.")

    hwtype             = ['reg','ext','fifo']

    if reg['hwtype'] not in hwtype:
        raise KeyError(f"hwtype '{reg['hwtype']}' must be in {hwtype}.")
    
    list_sw_re         = ['rw', 'ro','rw1c', 'rw0c', 'rw1s', 'rw0s','rsw1c', 'rcw1s', 'rsw0c']
    list_sw_we         = ['rw', 'wo','rw1c', 'rw0c', 'rw1s', 'rw0s','rsw1c', 'rcw1s', 'rsw0c'] 
    
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
        reg['address_write'].append(reg['name'])
    
    if reg['alias_write'] != None :
        if reg['alias_write'] == reg['name']:
            raise KeyError(f"Register '{reg['name']}', self aliases (alias_write {reg['alias_write']}).")

        reg_alias = next((item for item in csr['registers'] if item.get('name') == reg['alias_write']), None)
        
        if reg_alias == None:
            raise KeyError(f"Register '{reg['name']}', alias_write {reg['alias_write']} is not valid register.")

        check_key(reg_alias,'address_write',False,[])

        reg_alias['address_write'].append(reg['name'])
    
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
def load_schema():
    """
    Read the hjson schema of regtool (regtool_schema.hjson)

    :return: Return the schema
    """
    with open(os.path.join(os.path.dirname(os.path.abspath(__file__)),'regtool_schema.hjson'), 'r') as schema_file:
        return hjson.load(schema_file)

#--------------------------------------------
#--------------------------------------------
def dump_hjson(csr, suffix):
    """
    Dump the csr structure in <name>_<suffix>.hjson (debug)

    :param csr: Dictionary of csr
    :param suffix: Suffix of the file name
    """
    with open(csr['name']+'_'+suffix+'.hjson', 'w') as f:
        hjson.dump(csr, f, ensure_ascii=False)

#--------------------------------------------
#--------------------------------------------
def check_csr(csr, dump=False, source=None):
    """
    Validate the csr structure against the schema, fill the default values,
    check it and compute the derived fields used by the generators.

    :param csr: Dictionary of csr (content of the hjson file)
    :param dump: True : dump the structure after each step in <name>_dump[123].hjson
    :param source: Name of the hjson file, for the messages
    :return: Return the checked csr structure
    :raises jsonschema.exceptions.ValidationError: csr does not match the schema
    """

    schema  = load_schema()

    # Data validate
    try:
        validate(instance=csr, schema=schema)
        if source:
            print(f"The hjson file {source} is valide.")
    except jsonschema.exceptions.ValidationError as err:
        if source:
            print(f"The hjson file {source} is invalide.")
            print(f"  {err.message}")
        raise err

    if dump:
        dump_hjson(csr,'dump1')
    
    csr     = fill_defaults_recursive(schema, csr)

    if dump:
        dump_hjson(csr,'dump2')

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
        
    check_shared_address(csr)

    csr['size_addr'] = int(math.ceil(math.log2(addr_max+1)))
    addrmap.display()

    if dump:
        dump_hjson(csr,'dump3')

    return csr

#--------------------------------------------
#--------------------------------------------
def parse_hjson(file_path, dump=False, interface=None):
    """
    Read the file, then check it (see check_csr)
    
    :param file_path: Path to the hjson file
    :param dump: True : dump the structure after each step in <name>_dump[123].hjson
    :param interface: If set, replaces the interface of the hjson file
    :return: Return an hjson structure
    """

    # Open hjson file
    with open(file_path, 'r') as data_file:
        csr=hjson.load(data_file)

    if interface:
        csr['interface'] = interface

    return check_csr(csr, dump, file_path)

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
