"""
Module regtool.py
Command line of regtool : reads the CSR description (csr_model) and calls the
generators (gen_vhdl, gen_c, gen_markdown).
"""

import argparse
from   csr_model    import parse_hjson
from   gen_vhdl     import generate_vhdl_package, generate_vhdl_module
from   gen_c        import generate_c_header
from   gen_markdown import generate_doc_markdown

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

    csr          = parse_hjson(args.input_file, dump=True)
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
