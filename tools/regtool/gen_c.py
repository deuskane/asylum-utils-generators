"""
Module gen_c.py
C header generator of regtool.
"""

from   csr_model import parse_value

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
            regmap.setdefault(reg['address'],[]).append(reg['name'])
            
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
                
                for enum in field.get('enum', []):
                    file.write(f"// Enum        : {reg['name']}.{field['name']}.{enum['name']}\n")
                    file.write(f"// Description : {enum['desc']}\n")
                    value = parse_value(enum['value'])
                    file.write(f"#define {module.upper()}_{reg['name'].upper()}_{field['name'].upper()}_{enum['name'].upper()}     0x{value:X}\n")
                    file.write(f"#define {module.upper()}_{reg['name'].upper()}_{field['name'].upper()}_{enum['name'].upper()}_RAW (0x{value:X}<<{field['lsb']})\n")
                    file.write( "\n")

        file.write( "//----------------------------------\n")
        file.write(f"// Structure {module}_t\n")
        file.write( "//----------------------------------\n")

        # Last address covered
        curaddr = 0;
        
        # Define global struct containing all registers
        file.write(f"typedef struct {{\n")

        for addr in sorted(regmap.keys()):
            for i in range(curaddr, addr, csr['addr_offset']):
                file.write(f"  uint{csr['width']}_t __dummy_0x{i:X}__;\n")
            curaddr = addr+csr['addr_offset']
            # Shared address : member named <reg1>_<reg2>
            file.write(f"  uint{csr['width']}_t {'_'.join(regmap[addr])}; // 0x{addr:X}\n")
        file.write(f"}} {module}_t;\n")

        file.write(f"\n#endif // {module.upper()}_REGISTERS_H\n")
