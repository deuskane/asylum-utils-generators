"""
Module gen_markdown.py
Markdown documentation generator of regtool.
"""

#--------------------------------------------
#--------------------------------------------
def generate_doc_markdown(csr, output_path):
    module = csr['name']

    regmap = {}
        
    # Define structs for each register
    for reg in csr['registers']:
        regmap.setdefault(reg['address'],[]).append(reg['name'])

    
    with open(output_path, 'w') as file:
        file.write(f"# {csr['name']}\n")
        file.write(f"{csr['desc']}\n")
        file.write( "\n")
        file.write( "| Address | Registers |\n")
        file.write( "|---------|-----------|\n")
        for addr in sorted(regmap.keys()):
            file.write(f"|0x{addr:X}|{', '.join(regmap[addr])}|\n")
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
        
