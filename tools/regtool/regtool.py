import hjson

def read_register_description(file_path):
    with open(file_path, 'r') as file:
        return hjson.load(file)

def parse_init_value(init_value, width):
    if init_value.startswith('d'):
        return f"{int(init_value[1:]):0{width}b}"
    elif init_value.startswith('b'):
        return init_value[1:]
    elif init_value.startswith('x'):
        return f"{int(init_value[1:], 16):0{width}b}"
    else:
        raise ValueError(f"Invalid init value format: {init_value}")


def generate_c_header(registers, output_path):
    prefix = registers['name']
    
    with open(output_path, 'w') as file:
        file.write(f"#ifndef {prefix.upper()}_REGISTERS_H\n")
        file.write(f"#define {prefix.upper()}_REGISTERS_H\n\n")
        
        file.write("#include <stdint.h>\n\n")
        
        # Define structs for each register
        for reg in registers['registers']:
            file.write(f"// Register: {reg['name']}\n")
            file.write(f"// Address: {reg['address']}\n")
            file.write(f"// Description: {reg['description']}\n")
            file.write(f"typedef struct {{\n")
            for field in reg['fields']:
                file.write(f"    uint{field['width']}_t {field['name']}; // {field['description']}\n")
            file.write(f"    uint8_t re;\n")
            file.write(f"    uint8_t we;\n")
            file.write(f"}} {prefix}_{reg['name']}_t;\n\n")
        
        # Define global struct containing all registers
        file.write(f"typedef struct {{\n")
        for reg in registers['registers']:
            file.write(f"    {prefix}_{reg['name']}_t {reg['name']};\n")
        file.write(f"}} {prefix}_registers_t;\n\n")

        # Define base address and offsets for each register
        base_address = 0x40000000  # Example base address
        file.write(f"#define {prefix.upper()}_BASE_ADDRESS 0x{base_address:X}\n\n")
        for reg in registers['registers']:
            offset = int(reg['address'], 16)
            file.write(f"#define {prefix.upper()}_{reg['name'].upper()}_OFFSET 0x{offset:X}\n")

        file.write(f"\n#endif // {prefix.upper()}_REGISTERS_H\n")

def generate_vhdl_package(registers, output_path):
    prefix = registers['name']
    
    with open(output_path, 'w') as file:
        file.write(f"-- Generated VHDL Package for {prefix}\n\n")
        file.write("library IEEE;\n")
        file.write("use IEEE.STD_LOGIC_1164.ALL;\n")
        file.write("use IEEE.STD_LOGIC_ARITH.ALL;\n")
        file.write("use IEEE.STD_LOGIC_UNSIGNED.ALL;\n\n")
        
        file.write(f"package {prefix}_registers_pkg is\n\n")
        
        # Generate structs for each register
        for reg in registers['registers']:
            file.write(f"  -- Register: {reg['name']}\n")
            file.write(f"  -- Address: {reg['address']}\n")
            file.write(f"  -- Description: {reg['description']}\n")
            file.write(f"  type {prefix}_{reg['name']}_t is record\n")
            for field in reg['fields']:
                file.write(f"    {field['name']} : std_logic_vector({field['width']-1} downto 0);\n")
            file.write(f"    re : std_logic;\n")
            file.write(f"    we : std_logic;\n")
            file.write(f"  end record {prefix}_{reg['name']}_t;\n\n")
        
        # Generate global struct containing all registers
        file.write(f"  type {prefix}_registers_t is record\n")
        for reg in registers['registers']:
            file.write(f"    {reg['name']} : {prefix}_{reg['name']}_t;\n")
        file.write(f"  end record {prefix}_registers_t;\n\n")

        file.write(f"end package {prefix}_registers_pkg;\n\n")

        file.write(f"package body {prefix}_registers_pkg is\n\n")
        file.write(f"end package body {prefix}_registers_pkg;\n")

def generate_vhdl_module(registers, output_path):
    prefix = registers['name']
    async_read = registers.get('async_read', False)
    
    with open(output_path, 'w') as file:
        file.write(f"-- Generated VHDL Module for {prefix}\n\n")
        file.write("library IEEE;\n")
        file.write("use IEEE.STD_LOGIC_1164.ALL;\n")
        file.write("use IEEE.STD_LOGIC_ARITH.ALL;\n")
        file.write("use IEEE.STD_LOGIC_UNSIGNED.ALL;\n\n")

        # Generate VHDL entity and architecture
        file.write(f"entity {prefix}_registers is\n")
        file.write("    Port (\n")
        file.write("        clk : in STD_LOGIC;\n")
        file.write("        rst : in STD_LOGIC;\n")
        file.write("        addr : in STD_LOGIC_VECTOR (31 downto 0);\n")
        file.write("        data_in : in STD_LOGIC_VECTOR (31 downto 0);\n")
        file.write("        data_out : out STD_LOGIC_VECTOR (31 downto 0);\n")
        file.write("        we : in STD_LOGIC;\n")
        file.write(f"        csr2hw : out {prefix}_registers_t;\n")
        file.write(f"        hw2csr : in {prefix}_registers_t\n")
        file.write("    );\n")
        file.write(f"end entity {prefix}_registers;\n\n")

        file.write(f"architecture Behavioral of {prefix}_registers is\n")

        for reg in registers['registers']:
            init_values = ''.join([parse_init_value(field['init'], field['width']) for field in reg['fields']])
            signal_name = f"{reg['name']}_sig"
            bit_range = f"{reg['width']-1} downto 0"
            
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
            for reg in registers['registers']:
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
            for reg in registers['registers']:
                if reg['swaccess'] == 'rw' or reg['swaccess'] == 'ro':
                    file.write(f"                when x\"{reg['address']}\" =>\n")
                    file.write(f"                    data_out <= {reg['name']}_sig;\n")
                    file.write(f"                    {reg['name']}_re <= '1';\n")
            file.write("                when others =>\n")
            file.write("                    data_out <= (others => '0');\n")
            file.write("            end case;\n")
            file.write("        end if;\n")
            file.write("    end process;\n\n")

        for reg in registers['registers']:
            if reg['swaccess'] == 'rw' or reg['swaccess'] == 'wo':
                # Write process
                file.write("    process(clk, rst)\n")
                file.write("    begin\n")
                file.write("        if rst = '1' then\n")
                for field in reg['fields']:
                    init_value = parse_init_value(field['init'], field['width'])
                    bit_range = f"{field['lsb']}+{field['width']-1} downto {field['lsb']}"
                    file.write(f"            {reg['name']}_sig({bit_range}) <= \"{init_value}\";\n")
                file.write("        elsif rising_edge(clk) then\n")
                file.write(f"            if we = '1' and addr = x\"{reg['address']}\" then\n")
                file.write(f"                {reg['name']}_sig <= data_in({reg['width']-1} downto 0);\n")
                file.write(f"                {reg['name']}_we <= '1';\n")
                file.write("            end if;\n")
                file.write("        end if;\n")
                file.write("    end process;\n\n")

            # Assign output ports to signals
            if reg['swaccess'] == 'rw' or reg['swaccess'] == 'ro':
                file.write(f"    {reg['name']} <= {reg['name']}_sig;\n")

        file.write("\nend architecture Behavioral;\n")

def main():
    input_file          = 'examples/example1.hjson'
    vhdl_package_output = 'generated_registers_pkg.vhdl'
    vhdl_module_output  = 'generated_registers.vhdl'
    c_header_output     = 'generated_registers.h'
    
    registers = read_register_description(input_file)
    generate_vhdl_package (registers, vhdl_package_output)
    generate_vhdl_module  (registers, vhdl_module_output)
    generate_c_header     (registers, c_header_output)
    print(f"VHDL package generated in {vhdl_package_output}")
    print(f"VHDL module generated in {vhdl_module_output}")
    print(f"C header generated in {c_header_output}")

if __name__ == "__main__":
    main()
