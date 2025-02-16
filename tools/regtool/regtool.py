"""
Module regtool.py
Ce module contient des outils pour manipuler les registres.
"""

import hjson

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

        
    return csr

#--------------------------------------------
#--------------------------------------------
def parse_init_value(init_value, width):
    """
    Read the value and transform in binary
    
    :param init_value: Init value from hjson
    :param width: Width of the value
    :return: Return an hjson structure
    """
    if   init_value.startswith('b'):
        return init_value[1:]
    elif init_value.startswith('x'):
        return f"{int(init_value[1:], 16):0{width}b}"
    elif init_value.startswith('d'):
        return f"{int(init_value[1:]):0{width}b}"
    else:
        # default : decimal
        return f"{int(init_value):0{width}b}"

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
        file.write(f"#define {module.upper()}_REGISTERS_H\n\n")
        
        file.write("#include <stdint.h>\n\n")
        
        # Define structs for each register
        for reg in csr['registers']:
            file.write(f"// Register: {reg['name']}\n")
            file.write(f"// Address: {reg['address']}\n")
            file.write(f"// Description: {reg['desc']}\n")
            file.write(f"typedef struct {{\n")
            for field in reg['fields']:
                msb,lsb    = parse_bits(field['bits'])
                width      = msb-lsb+1

                file.write(f"    uint{width}_t {field['name']}; // {field['desc']}\n")
            file.write(f"    uint8_t re;\n")
            file.write(f"    uint8_t we;\n")
            file.write(f"}} {module}_{reg['name']}_t;\n\n")
        
        # Define global struct containing all registers
        file.write(f"typedef struct {{\n")
        for reg in csr['registers']:
            file.write(f"    {module}_{reg['name']}_t {reg['name']};\n")
        file.write(f"}} {module}_registers_t;\n\n")

        # Define base address and offsets for each register
        base_address = 0x40000000  # Example base address
        file.write(f"#define {module.upper()}_BASE_ADDRESS 0x{base_address:X}\n\n")
        for reg in csr['registers']:
            offset = int(reg['address'], 16)
            file.write(f"#define {module.upper()}_{reg['name'].upper()}_OFFSET 0x{offset:X}\n")

        file.write(f"\n#endif // {module.upper()}_REGISTERS_H\n")

#--------------------------------------------
#--------------------------------------------
def generate_vhdl_package(csr, output_path):
    module = csr['name']
    
    with open(output_path, 'w') as file:
        file.write(f"-- Generated VHDL Package for {module}\n\n")
        file.write("library IEEE;\n")
        file.write("use IEEE.STD_LOGIC_1164.ALL;\n")
        file.write("use IEEE.STD_LOGIC_ARITH.ALL;\n")
        file.write("use IEEE.STD_LOGIC_UNSIGNED.ALL;\n\n")
        
        file.write(f"package {module}_registers_pkg is\n\n")
        
        # Generate structs for each register
        for reg in csr['registers']:
            file.write(f"  -- Register: {reg['name']}\n")
            file.write(f"  -- Address: {reg['address']}\n")
            file.write(f"  -- Description: {reg['desc']}\n")
            file.write(f"  type {module}_{reg['name']}_t is record\n")
            for field in reg['fields']:
                msb,lsb    = parse_bits(field['bits'])
                width      = msb-lsb+1
                name       = field['name']
                file.write(f"    {name} : std_logic_vector({width}-1 downto 0);\n")
            file.write(f"    re : std_logic;\n")
            file.write(f"    we : std_logic;\n")
            file.write(f"  end record {module}_{reg['name']}_t;\n\n")
        
        # Generate global struct containing all registers
        file.write(f"  type {module}_registers_t is record\n")
        for reg in csr['registers']:
            file.write(f"    {reg['name']} : {module}_{reg['name']}_t;\n")
        file.write(f"  end record {module}_registers_t;\n\n")

        file.write(f"end package {module}_registers_pkg;\n\n")

        file.write(f"package body {module}_registers_pkg is\n\n")
        file.write(f"end package body {module}_registers_pkg;\n")

#--------------------------------------------
#--------------------------------------------
def generate_vhdl_module(csr, output_path):
    module = csr['name']
    async_read = csr.get('async_read', False)
    
    with open(output_path, 'w') as file:
        file.write(f"-- Generated VHDL Module for {module}\n\n")
        file.write("library IEEE;\n")
        file.write("use IEEE.STD_LOGIC_1164.ALL;\n")
        file.write("use IEEE.STD_LOGIC_ARITH.ALL;\n")
        file.write("use IEEE.STD_LOGIC_UNSIGNED.ALL;\n\n")

        # Generate VHDL entity and architecture
        file.write(f"entity {module}_registers is\n")
        file.write( "    Port (\n")
        file.write( "        clk      : in  STD_LOGIC;\n")
        file.write( "        rst      : in  STD_LOGIC;\n")
        file.write( "        addr     : in  STD_LOGIC_VECTOR (31 downto 0);\n")
        file.write( "        data_in  : in  STD_LOGIC_VECTOR (31 downto 0);\n")
        file.write( "        data_out : out STD_LOGIC_VECTOR (31 downto 0);\n")
        file.write( "        we       : in  STD_LOGIC;\n")
        file.write(f"        sw2hw    : out {module}_registers_t;\n")
        file.write(f"        hw2sw    : in  {module}_registers_t\n")
        file.write( "    );\n")
        file.write(f"end entity {module}_registers;\n\n")

        file.write(f"architecture rtl of {module}_registers is\n")

        for reg in csr['registers']:
            #msb,lsb    = parse_bits(field['bits'])
            #width      = msb-lsb+1
            width       = csr['width'] 
            init_values = ''.join([parse_init_value(field['init'], width) for field in reg['fields']])
            signal_name = f"{reg['name']}_sig"
            bit_range = f"{width}-1 downto 0"
            
            # Signal declaration
            file.write(f"    signal {signal_name} : std_logic_vector({bit_range}) := \"{init_values}\";\n")

            # RE and WE signals
            re_signal = f"{reg['name']}_re"
            we_signal = f"{reg['name']}_we"
            file.write(f"    signal {re_signal} : std_logic := '0';\n")
            file.write(f"    signal {we_signal} : std_logic := '0';\n")

        # Begin architecture body
        file.write("\nbegin\n\n")

        if async_read:
            # Asynchronous read process
            case_statement = (
                "    process(addr)\n"
                "    begin\n"
                "        case addr is\n"
            )
            for reg in csr['registers']:
                if reg['swaccess'] == 'rw' or reg['swaccess'] == 'ro':
                    case_statement += (
                        f"            when x\"{reg['address']}\" =>\n"
                        f"                data_out <= {reg['name']}_sig;\n"
                        f"                {reg['name']}_re <= '1';\n"
                    )
            case_statement += (
                "            when others =>\n"
                "                data_out <= (others => '0');\n"
                "        end case;\n"
                "    end process;\n\n"
            )
            file.write(case_statement)
        else:
            # Synchronous read process
            file.write("    process(clk)\n")
            file.write("    begin\n")
            file.write("        if rising_edge(clk) then\n")
            file.write("            case addr is\n")
            for reg in csr['registers']:
                if reg['swaccess'] == 'rw' or reg['swaccess'] == 'ro':
                    file.write(f"                when x\"{reg['address']}\" =>\n")
                    file.write(f"                    data_out <= {reg['name']}_sig;\n")
                    file.write(f"                    {reg['name']}_re <= '1';\n")
            file.write("                when others =>\n")
            file.write("                    data_out <= (others => '0');\n")
            file.write("            end case;\n")
            file.write("        end if;\n")
            file.write("    end process;\n\n")

        for reg in csr['registers']:
            if reg['swaccess'] == 'rw' or reg['swaccess'] == 'wo':
                # Write process
                file.write("    process(clk, rst)\n")
                file.write("    begin\n")
                file.write("        if rst = '1' then\n")
                for field in reg['fields']:
                    msb,lsb    = parse_bits(field['bits'])
                    width      = msb-lsb+1
                    init_value = parse_init_value(field['init'], width)
                    bit_range  = f"{msb} downto {lsb}"
                    file.write(f"            {reg['name']}_sig({bit_range}) <= \"{init_value}\";\n")
                file.write("        elsif rising_edge(clk) then\n")
                file.write(f"            if we = '1' and addr = x\"{reg['address']}\" then\n")
                file.write(f"                {reg['name']}_sig <= data_in({width}-1 downto 0);\n")
                file.write(f"                {reg['name']}_we <= '1';\n")
                file.write("            end if;\n")
                file.write("        end if;\n")
                file.write("    end process;\n\n")

            # Assign output ports to signals
            if reg['swaccess'] == 'rw' or reg['swaccess'] == 'ro':
                file.write(f"    {reg['name']} <= {reg['name']}_sig;\n")

        file.write("\nend architecture rtl;\n")

#--------------------------------------------
#--------------------------------------------
def main():
    input_file          = 'examples/example1.hjson'
    vhdl_package_output = 'generated_registers_pkg.vhdl'
    vhdl_module_output  = 'generated_registers.vhdl'
    c_header_output     = 'generated_registers.h'
    
    csr                 = parse_hjson(input_file)
    generate_vhdl_package (csr, vhdl_package_output)
    generate_vhdl_module  (csr, vhdl_module_output)
    generate_c_header     (csr, c_header_output)
    print(f"VHDL package generated in {vhdl_package_output}")
    print(f"VHDL module generated in {vhdl_module_output}")
    print(f"C header generated in {c_header_output}")

if __name__ == "__main__":
    main()
